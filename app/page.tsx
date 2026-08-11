"use client";

import { type CSSProperties, type Dispatch, type FormEvent, Fragment, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type SetStateAction, type WheelEvent as ReactWheelEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import dynamic from "next/dynamic";
import { PlayerCosmeticCard } from "./_components/player-cosmetic-card";
import { attachVenueAutocomplete, type VenuePlace } from "./googlePlacesClient";
import { GlobalRatingPanel } from "./global-rating-panel";
import {
  ADVANCED_TEST_VERSION,
  ATTRIBUTE_KEYS,
  FOOTBALL_RATING_ENGINE_VERSION,
  FREQUENCIES,
  INITIAL_TECHNICAL_QUESTIONS,
  INITIAL_TEST_VERSION,
  POSITION_LABELS,
  RESPONSE_OPTIONS,
  calculateAdvancedRatings,
  calculateApplicableAdvancedQuestions,
  calculateInitialRatings,
  roundRating,
  type AdvancedQuestion,
  type AnswerValue,
  type AttributeKey,
  type AttributeRatings,
  type FootballMode,
  type FrequencyId,
  type InitialRatingInput,
  type InitialRatingResult,
  type InitialTechnicalQuestionId,
  type PlayerPosition as AssessmentPosition,
} from "./laboratorio-ficha-jugador/_engine/player-rating-engine";
import { useAdminViewPreview } from "./admin-view-preview";
import { AdminViewPreviewButton, MobileAppNav, type MobileAppTab } from "./mobile-app-nav";
import {
  normalizePublicPlayerCosmeticsSnapshot,
  type PublicPlayerCosmeticsSnapshot,
} from "./player-cosmetics-contract";
import { clientWriteFetch, PWA_WRITE_REJECTED_EVENT } from "./pwa-client-bridge";
import {
  OUTFIELD_FACET_LABELS,
  RATING_COMPARISON_DELTAS,
  RATING_COMPARISON_OPTIONS,
  socialRatingDisclosure,
  type RatingComparison,
} from "./rating-system-v2";
import { supabase } from "./supabaseClient";
import { ThemeToggle } from "./theme-toggle";

const RewardBoxDemo = dynamic(
  () => import("./reward-box-demo").then((module) => module.RewardBoxDemo),
  { ssr: false },
);

const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
const googleAuthNonceKey = "pachanga-google-auth-nonce";
const googleAuthReturnKey = "pachanga-google-auth-return";
const playerPhotoPromptForChatGpt = `Utiliza la fotografía adjunta como referencia y recorta únicamente a la persona que aparece en ella.

Crea un retrato profesional desde los hombros hacia arriba, similar a la fotografía de un jugador utilizada en una carta de fútbol tipo FIFA.

Requisitos:

- Mantén exactamente la identidad, los rasgos faciales, el peinado, el tono de piel y la expresión de la persona.
- Elimina por completo el fondo y entrégalo con transparencia real.
- Incluye la cabeza completa, el cuello y ambos hombros.
- Coloca el cuerpo ligeramente girado y la cabeza mirando hacia la cámara, con una pose natural, segura y profesional.
- Centra correctamente a la persona y deja un pequeño margen transparente alrededor de la cabeza.
- Corrige suavemente la postura si fuera necesario, sin cambiar el aspecto físico.
- Mejora la iluminación, la nitidez y el contraste de manera realista.
- Conserva la ropa original, salvo que se indique expresamente otra vestimenta.
- No añadas marcos, textos, escudos, fondos, efectos, sombras exteriores ni elementos de una carta.
- No deformes la cara, no rejuvenezcas, no embellezcas en exceso y no inventes partes ocultas de forma poco natural.
- Acabado fotográfico realista, limpio y de alta resolución.
- Formato vertical, preparado para integrarse posteriormente en una carta de jugador.
- Salida final en PNG con fondo transparente.`;

const mobileNavigationTabs: Array<{ id: MobileSectionTabId; label: string }> = [
  { id: "inicio", label: "Inicio" },
  { id: "partido", label: "Partido" },
];

function createGoogleRawNonce() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes));
}

async function sha256Hex(value: string) {
  const encoded = new TextEncoder().encode(value);
  const buffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

type RatingFacet = "ritmo" | "tiro" | "pase" | "regate" | "defensa" | "fisico";
type RatingRole = "field" | "goalkeeper";
type MobileSectionTabId = "inicio" | "partido";
type ProfilePane = "ficha" | "ranking";
type PlayerProfileMode = "edit" | "viewer";
type MatchManagerPane = "proximo" | "alineacion" | "resultado" | "admin";
type ProfileReturnTarget = {
  matchPane: MatchManagerPane;
  mobileTab: MobileAppTab;
  profilePane: ProfilePane;
  scrollY: number | null;
  teamGalleryOpen: boolean;
};
type ProfileFocusTarget = "rating";

const matchManagerPaneLabels: Record<MatchManagerPane, string> = {
  proximo: "Próximo",
  alineacion: "Alineación",
  resultado: "Resultado",
  admin: "Admin",
};

type RatingVote = {
  id: string;
  voterId: string;
  voterName?: string;
  ratingRole?: RatingRole;
  source?: "advancedAssessment" | "initialAssessment";
  matchCount: number;
  createdAt: string;
  facets: Record<RatingFacet, number>;
};

type RatingEligibility = {
  canRate: boolean;
  firstRating: boolean;
  previousEvidenceId?: string;
  previousRatingAt?: string | null;
  reason?: string;
  requiredMatches: number;
  sharedMatches: number;
};

type PlayerRatingV2 = {
  baseFacets?: AttributeRatings;
  baseOverall?: number | null;
  calibratedFacets?: AttributeRatings;
  calibratedOverall?: number | null;
  currentFacetModifiers?: Partial<AttributeRatings>;
  currentFacets?: AttributeRatings;
  currentOverall?: number | null;
  domain?: "field" | "goalkeeper" | "goalkeeper_legacy";
  engineVersion?: string | null;
  evaluatorCount?: number;
  recalculatedAt?: string | null;
  reliability?: number;
};

type PositionLine = "Porteria" | "Defensa" | "Medio" | "Ataque";

type PlayerPosition =
  | "Portero"
  | "Defensa central"
  | "Lateral derecho"
  | "Lateral izquierdo"
  | "Carrilero"
  | "Pivote defensivo"
  | "Interior / volante"
  | "Mediapunta"
  | "Extremo derecho"
  | "Extremo izquierdo"
  | "Delantero centro"
  | "Segundo delantero"
  | "Mediocentro / pivote"
  | "Delantero / punta"
  | "Cierre"
  | "Ala derecha"
  | "Ala izquierda"
  | "Pívot"
  | "Porteria"
  | "Defensa"
  | "Medio"
  | "Ataque";

type MarketZone = {
  address?: string;
  city?: string;
  country?: string;
  lat?: number;
  lng?: number;
  name: string;
  placeId: string;
  province?: string;
  radiusKm: number;
};

type Player = {
  id: string;
  globalPlayerProfileId?: string;
  ownerUserId?: string;
  assessmentSummary?: PlayerAssessmentSummary;
  name: string;
  avatar?: string;
  avatarOffsetX?: number;
  avatarOffsetY?: number;
  phone?: string;
  birthDate?: string;
  goalkeeperOnly?: boolean;
  injured?: boolean;
  inactive?: boolean;
  importedRating?: number;
  importedRatingAt?: string;
  importedRatingFromGroup?: string;
  rating: number;
  ratings?: number[];
  ratingVotes?: RatingVote[];
  ratingV2?: PlayerRatingV2;
  position: PlayerPosition;
  outfieldPosition?: PlayerPosition;
  marketAvailability?: string;
  marketBio?: string;
  marketEnabled?: boolean;
  marketModalities?: MatchKind[];
  marketOpenToGroup?: boolean;
  marketOpenToGuest?: boolean;
  marketZones?: string;
  marketZonesGeo?: MarketZone[];
  goals: number;
  assists: number;
  appearances: number;
  wins: number;
  lateCancels: number;
};

function canEditPlayerOwnedFields({
  canUseAdminControls,
  currentUserId,
  hasRealTeam,
  isDemoMode,
  isRegisteredUser,
  player,
}: {
  canUseAdminControls: boolean;
  currentUserId?: string | null;
  hasRealTeam: boolean;
  isDemoMode: boolean;
  isRegisteredUser: boolean;
  player?: Pick<Player, "ownerUserId"> | null;
}) {
  return Boolean(
    player &&
      (isDemoMode ||
        canUseAdminControls ||
        (hasRealTeam && isRegisteredUser && currentUserId && player.ownerUserId === currentUserId)),
  );
}

type PlayerAssessmentKind = "advanced" | "initial";

type PlayerAssessmentSummaryItem = {
  completedAt?: string;
  engineVersion?: string;
  facets?: Partial<Record<RatingFacet, number>>;
  primaryPosition?: AssessmentPosition;
  questionnaireVersion?: string;
  rating?: number;
  reliability?: number;
};

type PlayerAssessmentSummary = {
  advanced?: PlayerAssessmentSummaryItem;
  initial?: PlayerAssessmentSummaryItem;
};

type PlayerAssessmentFlow = {
  advancedAnswers: Record<string, AnswerValue>;
  advancedStep: number;
  idempotencyKey: string;
  initial: InitialRatingInput;
  initialStep: number;
  kind: PlayerAssessmentKind;
  saving: boolean;
  targetPlayerId: string;
};

type RatingTrend = {
  current: number;
  direction: "down" | "flat" | "up";
  previous: number;
};

type AvatarDraft = {
  avatar: string;
  avatarOffsetX: number;
  avatarOffsetY: number;
};

type MatchPlayer = {
  playerId: string;
  status: "voy" | "duda" | "no";
  joinedAt?: string;
  paid?: boolean;
};

type PendingStatusChange = {
  nextStatus: MatchPlayer["status"];
  playerId: string;
};

type OpenMatchRequestStatus = "accepted" | "cancelled" | "pending" | "rejected";

type PublicMatchRequest = {
  avatar?: string;
  avatarOffsetX?: number;
  avatarOffsetY?: number;
  birthDate?: string;
  goalkeeperOnly: boolean;
  id: string;
  media: number;
  openMatchId: string;
  playerId?: string;
  position: PlayerPosition;
  requestedAt: string;
  requesterName: string;
  requesterProfileId?: string;
  requesterUserId: string;
  status: OpenMatchRequestStatus;
};

type PublicMatchRequestRow = {
  avatar: string | null;
  avatar_offset_x: number | string | null;
  avatar_offset_y: number | string | null;
  birth_date: string | null;
  goalkeeper_only: boolean | null;
  id: string;
  media: number | string | null;
  open_match_id: string | null;
  player_id: string | null;
  position: string | null;
  requested_at: string | null;
  requester_name: string | null;
  requester_profile_id: string | null;
  requester_user_id: string | null;
  status: string | null;
};

type MatchKind = "sala" | "futbol7" | "futbol11";
type RankingSort = "media" | "goles" | "partidos" | "ganados";
type BillingInterval = "month" | "year";
type BillingStatus = "trial" | "active" | "trialing" | "past_due" | "canceled" | "unpaid" | "incomplete";

type Venue = {
  address?: string;
  city?: string;
  country?: string;
  id: string;
  lat?: number;
  lng?: number;
  name: string;
  defaultCost: number;
  kind?: MatchKind;
  placeId?: string;
  province?: string;
};

type SiteSettings = {
  brand: string;
  subscriptionContributionEnabled: boolean;
  subscriptionContributionMonthlyAmount: number;
  subscriptionContributionPeriod: BillingInterval;
  subscriptionContributionYearlyAmount: number;
  title: string;
  subtitle: string;
  teamAColor: string;
  teamBColor: string;
};

type LineupSlotPlayerId = string | null;

type LineupSlots = {
  teamA?: LineupSlotPlayerId[];
  teamB?: LineupSlotPlayerId[];
};

type Match = {
  id: string;
  title: string;
  date: string;
  season?: string;
  place: string;
  configured?: boolean;
  venueId?: string;
  kind?: MatchKind;
  targetPlayers: number;
  fieldCost?: number;
  price?: number;
  payerId?: string;
  players: MatchPlayer[];
  reservesAttend?: boolean;
  reserveLimit?: number;
  scorers?: Array<{ playerId: string; goals: number }>;
  closed?: boolean;
  lineupClosed?: boolean;
  lineupSlots?: LineupSlots;
  scoreA?: number;
  scoreB?: number;
  teamA?: string[];
  teamB?: string[];
  teamPhoto?: string;
  publicGuestsPay?: boolean;
  publicMaxRating?: number;
  publicMinRating?: number;
  publicOpen?: boolean;
  publicOpenSlots?: number;
  publicPositions?: PublicMatchPosition[];
  publicRequiresApproval?: boolean;
};

type PublicMatchPosition = "Portero" | "Defensa" | "Medio" | "Ataque";

type MatchWeather = {
  cloudCover: number | null;
  condition: string;
  conditionType: string;
  feelsLike: number | null;
  forecastTime: string;
  humidity: number | null;
  precipitationProbability: number | null;
  temperature: number | null;
  windKmh: number | null;
};

type WeatherApiPayload = { available?: boolean; forecast?: MatchWeather; message?: string };

const weatherClientHourMs = 60 * 60 * 1000;
const weatherClientDayMs = 24 * weatherClientHourMs;
const weatherForecastClientLimitMs = 7 * weatherClientDayMs;
const weatherForecastClientFreshWindowMs = weatherClientDayMs;
const weatherClientShortCacheMs = 2 * weatherClientHourMs;
const weatherClientLongCacheMs = weatherClientDayMs;

const demoMatchWeather: MatchWeather = {
  cloudCover: 8,
  condition: "Sol",
  conditionType: "CLEAR",
  feelsLike: 33,
  forecastTime: "2026-08-05T21:00:00.000Z",
  humidity: 68,
  precipitationProbability: 0,
  temperature: 29,
  windKmh: 6,
};
const matchWeatherClientCache = new Map<string, { expiresAt: number; payload: WeatherApiPayload }>();

type PlayerScoreFn = (player: Player) => number;
type TeamBalanceSummary = ReturnType<typeof teamBalanceSummary>;
type MatchRatingImpact = {
  delta: number;
  notes: string[];
};
type PlayerFormState = {
  balanceScore: number;
  hasData: boolean;
  label: "En ritmo" | "Excelente" | "Normal" | "Sin ritmo" | "En recuperación" | "Fuera del grupo" | null;
  notes: string[];
  percent: number;
  recentAverage: number | null;
  reliability: number;
  status: "excellent" | "good" | "normal" | "low" | "injured" | "returning" | "inactive";
};
type TeamBalanceMetrics = {
  averageRating: number;
  goalsPerMatch: number;
  keeperCount: number;
  power: number;
  winRate: number;
};

type AppPayload = {
  activeMatchId: string;
  matches: Match[];
  players: Player[];
  siteSettings: SiteSettings;
  venues: Venue[];
};

type MemberRole = "owner" | "admin" | "player";

type RemoteTeam = {
  billingInterval: BillingInterval | null;
  billingStatus: BillingStatus;
  billingTrialFinalizedMatches: number;
  id: string;
  inviteToken: string;
  name: string;
  ownerId: string | null;
  payload: AppPayload;
  payloadRevision: number;
  ratingsEnabled: boolean;
  role: MemberRole;
  stripeCustomerId: string | null;
  stripeCurrentPeriodEnd: string | null;
  stripePriceId: string | null;
  stripeSubscriptionId: string | null;
  teamCode: string;
};

type PlayerImportCandidate = {
  appearances: number;
  groupId: string;
  groupName: string;
  inactive: boolean;
  key: string;
  lastActivity: number;
  media: number;
  player: Player;
};

type RemoteMember = {
  displayName: string;
  role: MemberRole;
  userId: string;
};

type TeamBackup = {
  createdAt: string;
  groupName: string;
  id: string;
  matchCount: number;
  playerCount: number;
  reason: string;
  sourceGroupId: string | null;
  teamCode: string | null;
};

type IncomingSharedLink = {
  hasAdminInvite: boolean;
  hasInvite: boolean;
  hasMatch: boolean;
  teamCode: string | null;
};

export type HomeEntryRoute = {
  adminInviteToken?: string;
  inviteToken?: string;
  matchId?: string;
  teamCode?: string;
};

type RemotePayloadCommit = {
  billing_interval?: BillingInterval | null;
  billing_status?: BillingStatus | string | null;
  billing_trial_finalized_matches?: number | string | null;
  payload?: Partial<AppPayload>;
  payload_revision?: number | string;
  confirmedRevision?: number | string;
  ratingsEnabled?: boolean;
  ratings_enabled?: boolean;
  stripe_customer_id?: string | null;
  stripe_current_period_end?: string | null;
  stripe_price_id?: string | null;
  stripe_subscription_id?: string | null;
  updated_at?: string;
};

function demoVotes(playerId: string, rows: Array<[number, string, Record<RatingFacet, number>]>, ratingRole: RatingRole = "field"): RatingVote[] {
  return rows.map(([matchCount, createdAt, facets], index) => ({
    id: `rv-${playerId}-${index + 1}`,
    voterId: "demo",
    voterName: "Demo",
    ratingRole,
    matchCount,
    createdAt,
    facets,
  }));
}

const seedPlayers: Player[] = [
  { id: "p1", name: "Carlos", phone: "600 111 222", goalkeeperOnly: false, rating: 8, position: "Delantero / punta", goals: 18, assists: 7, appearances: 12, wins: 7, lateCancels: 1, ratingVotes: demoVotes("p1", [[3, "2026-06-10T23:00:00", { ritmo: 7, tiro: 8, pase: 6, regate: 7, defensa: 4, fisico: 7 }], [6, "2026-06-24T23:00:00", { ritmo: 8, tiro: 8, pase: 7, regate: 8, defensa: 5, fisico: 8 }], [9, "2026-07-08T23:00:00", { ritmo: 8, tiro: 9, pase: 7, regate: 8, defensa: 5, fisico: 8 }], [12, "2026-07-23T23:00:00", { ritmo: 8, tiro: 9, pase: 8, regate: 8, defensa: 5, fisico: 8 }]]) },
  { id: "p2", name: "Manu", phone: "600 222 333", rating: 7, position: "Mediocentro / pivote", goals: 10, assists: 13, appearances: 11, wins: 8, lateCancels: 0, ratingVotes: demoVotes("p2", [[3, "2026-06-10T23:00:00", { ritmo: 6, tiro: 5, pase: 8, regate: 6, defensa: 6, fisico: 7 }], [6, "2026-06-24T23:00:00", { ritmo: 6, tiro: 6, pase: 8, regate: 7, defensa: 7, fisico: 7 }], [8, "2026-07-08T23:00:00", { ritmo: 6, tiro: 6, pase: 9, regate: 7, defensa: 7, fisico: 7 }], [11, "2026-07-23T23:00:00", { ritmo: 7, tiro: 6, pase: 9, regate: 7, defensa: 8, fisico: 7 }]]) },
  { id: "p3", name: "Pablo", phone: "600 333 444", rating: 6, position: "Defensa central", goals: 5, assists: 4, appearances: 10, wins: 5, lateCancels: 2, ratingVotes: demoVotes("p3", [[3, "2026-06-10T23:00:00", { ritmo: 5, tiro: 4, pase: 5, regate: 5, defensa: 7, fisico: 6 }], [6, "2026-06-24T23:00:00", { ritmo: 5, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }], [10, "2026-07-23T23:00:00", { ritmo: 6, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }]]) },
  { id: "p4", name: "Rafa", phone: "600 444 555", goalkeeperOnly: true, rating: 7, position: "Portero", goals: 1, assists: 2, appearances: 9, wins: 4, lateCancels: 0, ratingVotes: demoVotes("p4", [[3, "2026-06-10T23:00:00", { ritmo: 6, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }], [6, "2026-07-03T23:00:00", { ritmo: 6, tiro: 4, pase: 7, regate: 5, defensa: 9, fisico: 7 }], [9, "2026-07-23T23:00:00", { ritmo: 6, tiro: 4, pase: 7, regate: 6, defensa: 9, fisico: 7 }]], "goalkeeper") },
  { id: "p5", name: "Dani", phone: "600 555 666", rating: 5, position: "Interior / volante", goals: 6, assists: 3, appearances: 8, wins: 3, lateCancels: 1, ratingVotes: demoVotes("p5", [[3, "2026-06-10T23:00:00", { ritmo: 5, tiro: 5, pase: 5, regate: 6, defensa: 5, fisico: 5 }], [6, "2026-06-24T23:00:00", { ritmo: 6, tiro: 5, pase: 6, regate: 6, defensa: 5, fisico: 5 }], [8, "2026-07-23T23:00:00", { ritmo: 6, tiro: 6, pase: 6, regate: 6, defensa: 5, fisico: 6 }]]) },
  { id: "p6", name: "Alex", phone: "600 666 777", rating: 6, position: "Defensa central", goals: 4, assists: 8, appearances: 9, wins: 6, lateCancels: 0, ratingVotes: demoVotes("p6", [[3, "2026-06-10T23:00:00", { ritmo: 5, tiro: 4, pase: 6, regate: 5, defensa: 7, fisico: 6 }], [6, "2026-06-24T23:00:00", { ritmo: 6, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }], [9, "2026-07-23T23:00:00", { ritmo: 6, tiro: 5, pase: 7, regate: 5, defensa: 8, fisico: 7 }]]) },
  { id: "p7", name: "Sergio", phone: "600 777 888", rating: 8, position: "Delantero / punta", goals: 15, assists: 5, appearances: 8, wins: 5, lateCancels: 1, ratingVotes: demoVotes("p7", [[3, "2026-06-10T23:00:00", { ritmo: 7, tiro: 7, pase: 6, regate: 7, defensa: 4, fisico: 7 }], [5, "2026-07-07T23:00:00", { ritmo: 8, tiro: 8, pase: 6, regate: 8, defensa: 4, fisico: 7 }], [8, "2026-07-23T23:00:00", { ritmo: 9, tiro: 8, pase: 6, regate: 8, defensa: 4, fisico: 7 }]]) },
  { id: "p8", name: "Javi", phone: "600 888 999", rating: 5, position: "Lateral derecho", goals: 3, assists: 6, appearances: 7, wins: 2, lateCancels: 3, ratingVotes: demoVotes("p8", [[3, "2026-06-10T23:00:00", { ritmo: 6, tiro: 4, pase: 5, regate: 5, defensa: 5, fisico: 5 }], [7, "2026-07-23T23:00:00", { ritmo: 7, tiro: 4, pase: 5, regate: 6, defensa: 6, fisico: 5 }]]) },
  { id: "p9", name: "Nico", phone: "600 999 000", rating: 5, position: "Ala izquierda", goals: 2, assists: 2, appearances: 2, wins: 1, lateCancels: 0 },
  { id: "p10", name: "Pedro", phone: "601 111 222", rating: 6, position: "Cierre", goals: 7, assists: 2, appearances: 4, wins: 2, lateCancels: 0 },
  { id: "p11", name: "Alberto", phone: "601 222 333", rating: 5, position: "Mediapunta", goals: 0, assists: 1, appearances: 1, wins: 0, lateCancels: 0 },
  { id: "p12", name: "Carlitos", phone: "601 333 444", rating: 6, position: "Extremo derecho", goals: 9, assists: 4, appearances: 6, wins: 4, lateCancels: 1 },
  { id: "p13", name: "Vicente", phone: "601 444 555", rating: 5, position: "Lateral izquierdo", goals: 1, assists: 2, appearances: 5, wins: 2, lateCancels: 0 },
  { id: "p14", name: "Mario", phone: "601 555 666", goalkeeperOnly: true, rating: 6, position: "Portero", goals: 0, assists: 0, appearances: 3, wins: 1, lateCancels: 0 },
  { id: "p15", name: "Hugo", phone: "601 666 777", injured: true, rating: 7, position: "Defensa central", goals: 4, assists: 1, appearances: 6, wins: 2, lateCancels: 0 },
  { id: "p16", name: "Rubén", phone: "601 777 888", inactive: true, rating: 6, position: "Interior / volante", goals: 6, assists: 7, appearances: 9, wins: 4, lateCancels: 1 },
  { id: "p17", name: "Iván", phone: "601 888 999", rating: 4, position: "Ala derecha", goals: 1, assists: 1, appearances: 0, wins: 0, lateCancels: 0 },
  { id: "p18", name: "Óscar", phone: "601 999 000", rating: 7, position: "Pívot", goals: 12, assists: 3, appearances: 5, wins: 3, lateCancels: 0 },
];

const seedVenues: Venue[] = [
  { id: "v1", name: "Polideportivo La Mina", address: "Sant Adrià de Besòs, Barcelona", city: "Sant Adrià de Besòs", defaultCost: 56, kind: "futbol7" },
  { id: "v2", name: "Pista El Parque", address: "Barcelona, Barcelona", city: "Barcelona", defaultCost: 42, kind: "sala" },
  { id: "v3", name: "Municipal Norte", address: "Sabadell, Barcelona", city: "Sabadell", defaultCost: 110, kind: "futbol11" },
];

function demoMatchPlayers(playerIds: string[], paidIds: string[] = playerIds): MatchPlayer[] {
  return playerIds.map((playerId) => ({ playerId, status: "voy" as const, paid: paidIds.includes(playerId) }));
}

const demoTeamPhoto = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 320 180'%3E%3Cdefs%3E%3ClinearGradient id='sky' x1='0' y1='0' x2='1' y2='1'%3E%3Cstop stop-color='%231b2f46'/%3E%3Cstop offset='.55' stop-color='%23154736'/%3E%3Cstop offset='1' stop-color='%23071110'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='320' height='180' fill='url(%23sky)'/%3E%3Cpath d='M0 132h320v48H0z' fill='%23216d42'/%3E%3Cpath d='M0 146h320M46 132v48M104 132v48M162 132v48M220 132v48M278 132v48' stroke='%23ffffff' stroke-opacity='.28' stroke-width='2'/%3E%3Ccircle cx='160' cy='154' r='23' fill='none' stroke='%23ffffff' stroke-opacity='.45' stroke-width='3'/%3E%3Cg fill='%23f5f2e8'%3E%3Ccircle cx='72' cy='76' r='16'/%3E%3Cpath d='M45 126c6-25 48-25 54 0z'/%3E%3Ccircle cx='128' cy='65' r='15'/%3E%3Cpath d='M102 126c6-27 47-27 53 0z'/%3E%3Ccircle cx='188' cy='70' r='15'/%3E%3Cpath d='M162 126c6-26 47-26 53 0z'/%3E%3Ccircle cx='248' cy='76' r='16'/%3E%3Cpath d='M221 126c6-25 48-25 54 0z'/%3E%3C/g%3E%3Ctext x='160' y='36' text-anchor='middle' font-family='Arial,sans-serif' font-size='18' font-weight='800' fill='%23c8ef5d'%3EPACHANGAS IQ%3C/text%3E%3C/svg%3E";

const seedMatches: Match[] = [
  {
    id: "m1",
    title: "Demo jueves 21:00",
    date: "2026-07-30T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    configured: true,
    payerId: "p2",
    reservesAttend: true,
    reserveLimit: 2,
    lineupClosed: false,
    players: [
      { playerId: "p4", status: "voy", joinedAt: "2026-07-20T09:00:00", paid: true },
      { playerId: "p14", status: "voy", joinedAt: "2026-07-20T09:03:00", paid: false },
      { playerId: "p1", status: "voy", joinedAt: "2026-07-20T09:10:00", paid: true },
      { playerId: "p2", status: "voy", joinedAt: "2026-07-20T09:14:00", paid: false },
      { playerId: "p3", status: "voy", joinedAt: "2026-07-20T09:21:00", paid: true },
      { playerId: "p5", status: "voy", joinedAt: "2026-07-20T09:28:00", paid: false },
      { playerId: "p6", status: "voy", joinedAt: "2026-07-20T09:35:00", paid: true },
      { playerId: "p7", status: "voy", joinedAt: "2026-07-20T09:40:00", paid: false },
      { playerId: "p8", status: "voy", joinedAt: "2026-07-20T09:45:00", paid: false },
      { playerId: "p10", status: "voy", joinedAt: "2026-07-20T09:51:00", paid: false },
      { playerId: "p11", status: "voy", joinedAt: "2026-07-20T09:58:00", paid: false },
      { playerId: "p12", status: "voy", joinedAt: "2026-07-20T10:02:00", paid: true },
      { playerId: "p13", status: "voy", joinedAt: "2026-07-20T10:10:00", paid: false },
      { playerId: "p18", status: "voy", joinedAt: "2026-07-20T10:15:00", paid: false },
      { playerId: "p9", status: "voy", joinedAt: "2026-07-20T10:35:00", paid: false },
      { playerId: "p17", status: "voy", joinedAt: "2026-07-20T10:46:00", paid: false },
      { playerId: "p15", status: "no" },
      { playerId: "p16", status: "no" },
    ],
  },
  {
    id: "m2",
    title: "Demo sala rápida",
    date: "2026-07-23T21:00",
    place: "Pista El Parque",
    venueId: "v2",
    kind: "sala",
    targetPlayers: 10,
    fieldCost: 42,
    configured: true,
    payerId: "p1",
    closed: true,
    scoreA: 5,
    scoreB: 3,
    teamPhoto: demoTeamPhoto,
    teamA: ["p4", "p1", "p2", "p7", "p12"],
    teamB: ["p14", "p3", "p5", "p6", "p8"],
    scorers: [
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 2 },
      { playerId: "p12", goals: 1 },
      { playerId: "p5", goals: 1 },
      { playerId: "p6", goals: 1 },
      { playerId: "p8", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p1", "p2", "p7", "p12", "p14", "p3", "p5", "p6", "p8"]),
  },
  {
    id: "m3",
    title: "Demo 7v7 igualada",
    date: "2026-07-16T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    configured: true,
    payerId: "p2",
    closed: true,
    scoreA: 4,
    scoreB: 4,
    teamPhoto: demoTeamPhoto,
    teamA: ["p4", "p6", "p8", "p13", "p1", "p7", "p10"],
    teamB: ["p14", "p3", "p5", "p2", "p11", "p12", "p18"],
    scorers: [
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 1 },
      { playerId: "p10", goals: 1 },
      { playerId: "p18", goals: 2 },
      { playerId: "p12", goals: 1 },
      { playerId: "p5", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p6", "p8", "p13", "p1", "p7", "p10", "p14", "p3", "p5", "p2", "p11", "p12", "p18"], ["p4", "p6", "p1", "p14", "p3", "p2", "p18"]),
  },
  {
    id: "m4",
    title: "Demo lunes sala",
    date: "2026-07-09T20:30",
    place: "Pista El Parque",
    venueId: "v2",
    kind: "sala",
    targetPlayers: 10,
    fieldCost: 42,
    configured: true,
    payerId: "p3",
    closed: true,
    scoreA: 6,
    scoreB: 2,
    teamPhoto: demoTeamPhoto,
    teamA: ["p4", "p1", "p2", "p7", "p18"],
    teamB: ["p14", "p3", "p5", "p6", "p12"],
    scorers: [
      { playerId: "p18", goals: 3 },
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 1 },
      { playerId: "p12", goals: 1 },
      { playerId: "p5", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p1", "p2", "p7", "p18", "p14", "p3", "p5", "p6", "p12"], ["p1", "p2", "p18", "p3", "p12"]),
  },
  {
    id: "m5",
    title: "Demo jueves 7v7",
    date: "2026-07-02T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    configured: true,
    payerId: "p6",
    closed: true,
    scoreA: 3,
    scoreB: 5,
    teamPhoto: demoTeamPhoto,
    teamA: ["p4", "p3", "p8", "p13", "p5", "p11", "p12"],
    teamB: ["p14", "p6", "p10", "p2", "p1", "p7", "p18"],
    scorers: [
      { playerId: "p12", goals: 2 },
      { playerId: "p5", goals: 1 },
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 2 },
      { playerId: "p18", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p3", "p8", "p13", "p5", "p11", "p12", "p14", "p6", "p10", "p2", "p1", "p7", "p18"], ["p4", "p8", "p12", "p14", "p6", "p1", "p7"]),
  },
  {
    id: "m6",
    title: "Demo municipal 11",
    date: "2026-06-25T22:00",
    place: "Municipal Norte",
    venueId: "v3",
    kind: "futbol11",
    targetPlayers: 22,
    fieldCost: 110,
    configured: true,
    payerId: "p7",
    closed: true,
    scoreA: 2,
    scoreB: 1,
    teamPhoto: demoTeamPhoto,
    teamA: ["p4", "p3", "p6", "p8", "p13", "p2", "p5", "p11", "p1", "p7", "p12"],
    teamB: ["p14", "p10", "p15", "p16", "p9", "p17", "p18"],
    scorers: [
      { playerId: "p7", goals: 1 },
      { playerId: "p1", goals: 1 },
      { playerId: "p18", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p3", "p6", "p8", "p13", "p2", "p5", "p11", "p1", "p7", "p12", "p14", "p10", "p15", "p16", "p9", "p17", "p18"], ["p4", "p3", "p6", "p2", "p1", "p7", "p14", "p10", "p18"]),
  },
  {
    id: "m7",
    title: "Demo primera prueba",
    date: "2026-06-18T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 50,
    configured: true,
    payerId: "p4",
    closed: true,
    scoreA: 1,
    scoreB: 3,
    teamPhoto: demoTeamPhoto,
    teamA: ["p4", "p3", "p8", "p13", "p5", "p11", "p12"],
    teamB: ["p14", "p6", "p10", "p2", "p1", "p7", "p18"],
    scorers: [
      { playerId: "p12", goals: 1 },
      { playerId: "p1", goals: 1 },
      { playerId: "p7", goals: 1 },
      { playerId: "p18", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p3", "p8", "p13", "p5", "p11", "p12", "p14", "p6", "p10", "p2", "p1", "p7", "p18"], ["p4", "p3", "p12", "p14", "p2", "p7"]),
  },
];

const storageKey = "pachanga-iq-v3";
const profileNameKey = "pachanga-iq-profile-name";
const demoTeamOptionId = "__pachangas_demo__";
const freeTrialMatchLimit = 2;

const backupReasonLabels: Record<string, string> = {
  equipo_borrado: "Antes de borrar equipo",
  manual: "Copia manual",
  partido_finalizado: "Partido finalizado",
  partido_guardado: "Partido guardado",
};

function defaultPayload(): AppPayload {
  return {
    activeMatchId: seedMatches[0].id,
    matches: seedMatches,
    players: seedPlayers,
    siteSettings: defaultSiteSettings,
    venues: seedVenues,
  };
}

const defaultSiteSettings: SiteSettings = {
  brand: "Pachangas IQ",
  subscriptionContributionEnabled: false,
  subscriptionContributionMonthlyAmount: 5.99,
  subscriptionContributionPeriod: "year",
  subscriptionContributionYearlyAmount: 64.99,
  title: "El grupo del partido, pero con memoria.",
  subtitle: "Confirma gente, guarda resultados y monta equipos equilibrados sin discutir media hora en WhatsApp.",
  teamAColor: "#2157a8",
  teamBColor: "#d93025",
};

function GoogleLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 18 18">
      <path fill="#4285f4" d="M17.6 9.2c0-.6-.1-1.1-.2-1.6H9v3.1h4.8a4.1 4.1 0 0 1-1.8 2.7v2.2h2.8a8.4 8.4 0 0 0 2.8-6.4Z" />
      <path fill="#34a853" d="M9 18c2.4 0 4.4-.8 5.8-2.2L12 13.5c-.8.5-1.8.8-3 .8a5.3 5.3 0 0 1-5-3.7H1.1v2.3A8.8 8.8 0 0 0 9 18Z" />
      <path fill="#fbbc05" d="M4 10.6a5.3 5.3 0 0 1 0-3.3V5H1.1a9 9 0 0 0 0 7.9l2.9-2.3Z" />
      <path fill="#ea4335" d="M9 3.6c1.3 0 2.5.5 3.4 1.3l2.5-2.5A8.5 8.5 0 0 0 9 0a8.8 8.8 0 0 0-7.9 5L4 7.3a5.3 5.3 0 0 1 5-3.7Z" />
    </svg>
  );
}

function SearchLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M10.8 4a6.8 6.8 0 0 1 5.4 10.9l4 4-1.4 1.4-4-4A6.8 6.8 0 1 1 10.8 4Zm0 2a4.8 4.8 0 1 0 0 9.6 4.8 4.8 0 0 0 0-9.6Z" />
    </svg>
  );
}

function BoardLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M4 4h16v16H4V4Zm2 2v12h12V6H6Zm2 7.7 1.35-1.35 2.15 2.15 4.15-4.15L17 11.7l-5.5 5.5L8 13.7Z" />
    </svg>
  );
}

function EyeSlashLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="m3.28 2.22 18.5 18.5-1.42 1.42-3.2-3.2A11.7 11.7 0 0 1 12 20C6.4 20 2.4 16.36 1 12c.62-1.94 1.82-3.65 3.4-4.97L1.86 4.5l1.42-2.28ZM6.1 8.73A9.56 9.56 0 0 0 3.16 12c1.2 3.16 4.42 6 8.84 6 1.2 0 2.3-.2 3.3-.57l-2.12-2.12A4 4 0 0 1 8.7 10.82L6.1 8.73ZM12 4c5.6 0 9.6 3.64 11 8a11.1 11.1 0 0 1-2.72 4.36l-1.42-1.42A9.02 9.02 0 0 0 20.84 12C19.64 8.84 16.42 6 12 6c-.9 0-1.76.12-2.55.35L7.86 4.76A11.6 11.6 0 0 1 12 4Zm0 4a4 4 0 0 1 4 4c0 .38-.05.74-.15 1.08L10.92 8.15C11.26 8.05 11.62 8 12 8Z" />
    </svg>
  );
}

function EraserLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M15.7 4.3a2.4 2.4 0 0 1 3.4 0l1.6 1.6a2.4 2.4 0 0 1 0 3.4L10.1 19.9H4.9L2.3 17.3a2.4 2.4 0 0 1 0-3.4l13.4-9.6Zm1.4 1.4L10.8 12l3.2 3.2 5.3-5.3a.4.4 0 0 0 0-.56l-1.6-1.6a.4.4 0 0 0-.6 0ZM4.6 15.3a.4.4 0 0 0 0 .56L5.7 17h3.55l3.35-3.35-3.2-3.2-4.8 4.85ZM13 20h9v2h-9v-2Z" />
    </svg>
  );
}

function GoogleSignInButton({
  className = "",
  disabled,
  label,
  onClick,
}: {
  className?: string;
  disabled?: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button className={`google-signin-button${className ? ` ${className}` : ""}`} type="button" onClick={onClick} disabled={disabled}>
      <GoogleLogo />
      <span>{label}</span>
    </button>
  );
}

function WhatsAppLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M12 3.3a8.5 8.5 0 0 0-7.2 13L4 20.8l4.6-1.2A8.5 8.5 0 1 0 12 3.3Zm0 1.7a6.8 6.8 0 1 1-3.1 12.8l-.3-.2-2.4.6.6-2.3-.2-.4A6.8 6.8 0 0 1 12 5Zm-3.1 3.6c-.2 0-.5.1-.7.4-.2.3-.8.8-.8 1.9s.8 2.2 1 2.4c.1.2 1.7 2.8 4.2 3.8 2.1.8 2.5.5 3 .5.4 0 1.4-.6 1.6-1.1.2-.5.2-1 .1-1.1-.1-.1-.2-.2-.5-.3l-1.6-.8c-.2-.1-.4-.1-.6.2l-.7.9c-.1.2-.3.2-.5.1-.3-.1-1.1-.4-2-1.2-.7-.7-1.2-1.5-1.4-1.7-.1-.3 0-.4.1-.5l.4-.5c.1-.2.2-.3.3-.5.1-.2 0-.3 0-.5L10 9c-.2-.4-.4-.4-.6-.4h-.5Z" />
    </svg>
  );
}

function CopyLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M8 7.5A2.5 2.5 0 0 1 10.5 5h7A2.5 2.5 0 0 1 20 7.5v7a2.5 2.5 0 0 1-2.5 2.5H16v1.5A2.5 2.5 0 0 1 13.5 21h-7A2.5 2.5 0 0 1 4 18.5v-7A2.5 2.5 0 0 1 6.5 9H8V7.5Zm2 1.5h3.5A2.5 2.5 0 0 1 16 11.5V15h1.5a.5.5 0 0 0 .5-.5v-7a.5.5 0 0 0-.5-.5h-7a.5.5 0 0 0-.5.5V9Zm-3.5 2a.5.5 0 0 0-.5.5v7a.5.5 0 0 0 .5.5h7a.5.5 0 0 0 .5-.5v-7a.5.5 0 0 0-.5-.5h-7Z" />
    </svg>
  );
}

function TrashLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M9 4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2h4v2H5V4h4Zm-2 4h10l-.7 11.2A3 3 0 0 1 13.3 22h-2.6a3 3 0 0 1-3-2.8L7 8Zm3 2 .4 9h1.7l-.3-9H10Zm3.2 0-.3 9h1.7l.4-9h-1.8Z" />
    </svg>
  );
}

function HospitalLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M4 21V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16h-6v-5h-4v5H4Zm2-2h2v-5h8v5h2V5H6v14Zm5-6v-3H8V8h3V5h2v3h3v2h-3v3h-2Z" />
    </svg>
  );
}

function UserOffLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M10 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm0 2c-3.6 0-7 1.8-7 4.8V20h10.7A6.9 6.9 0 0 1 13 17c0-1.4.4-2.7 1.1-3.8A12 12 0 0 0 10 13Zm8 1a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm-2.2 3.2 1.4-1.4.8.8.8-.8 1.4 1.4-.8.8.8.8-1.4 1.4-.8-.8-.8.8-1.4-1.4.8-.8-.8-.8Z" />
    </svg>
  );
}

const matchKinds: Record<MatchKind, { label: string; targetPlayers: number; teamSize: number }> = {
  sala: { label: "Fútbol sala", targetPlayers: 10, teamSize: 5 },
  futbol7: { label: "Fútbol 7", targetPlayers: 14, teamSize: 7 },
  futbol11: { label: "Fútbol 11", targetPlayers: 22, teamSize: 11 },
};

const rankingSortLabels: Record<RankingSort, string> = {
  media: "Media",
  goles: "Goles",
  partidos: "Partidos",
  ganados: "Ganados",
};

function starterMatch(baseDate = "2026-07-30T21:00", kind: MatchKind = "futbol7"): Match {
  const date = nextMatchDate(baseDate);

  return {
    id: id(),
    title: "Nueva pachanga",
    date,
    season: seasonKey(date),
    place: "Campo por confirmar",
    configured: false,
    kind,
    targetPlayers: matchKinds[kind].targetPlayers,
    fieldCost: 0,
    players: [],
    reservesAttend: false,
    reserveLimit: 0,
  };
}

function emptyTeamPayload(teamName: string): AppPayload {
  const match = starterMatch(undefined, "futbol7");
  return {
    activeMatchId: match.id,
    matches: [match],
    players: [],
    siteSettings: {
      ...defaultSiteSettings,
      brand: displayName(teamName) || defaultSiteSettings.brand,
      title: "Tu grupo de pachangas, desde cero.",
      subtitle: "Crea tu ficha, selecciona un partido y apúntate.",
    },
    venues: [],
  };
}

const positionOptionsByKind: Record<MatchKind, Array<{ value: PlayerPosition; line: PositionLine; short: string }>> = {
  futbol11: [
    { value: "Portero", line: "Porteria", short: "POR" },
    { value: "Defensa central", line: "Defensa", short: "DFC" },
    { value: "Lateral derecho", line: "Defensa", short: "LD" },
    { value: "Lateral izquierdo", line: "Defensa", short: "LI" },
    { value: "Carrilero", line: "Defensa", short: "CAR" },
    { value: "Pivote defensivo", line: "Medio", short: "MCD" },
    { value: "Interior / volante", line: "Medio", short: "INT" },
    { value: "Mediapunta", line: "Medio", short: "MP" },
    { value: "Extremo derecho", line: "Ataque", short: "ED" },
    { value: "Extremo izquierdo", line: "Ataque", short: "EI" },
    { value: "Delantero centro", line: "Ataque", short: "DC" },
    { value: "Segundo delantero", line: "Ataque", short: "SD" },
  ],
  futbol7: [
    { value: "Portero", line: "Porteria", short: "POR" },
    { value: "Defensa central", line: "Defensa", short: "DFC" },
    { value: "Lateral derecho", line: "Defensa", short: "LD" },
    { value: "Lateral izquierdo", line: "Defensa", short: "LI" },
    { value: "Mediocentro / pivote", line: "Medio", short: "PIV" },
    { value: "Interior / volante", line: "Medio", short: "INT" },
    { value: "Delantero / punta", line: "Ataque", short: "DEL" },
  ],
  sala: [
    { value: "Portero", line: "Porteria", short: "POR" },
    { value: "Cierre", line: "Defensa", short: "CIE" },
    { value: "Ala derecha", line: "Medio", short: "ALD" },
    { value: "Ala izquierda", line: "Medio", short: "ALI" },
    { value: "Pívot", line: "Ataque", short: "PIV" },
  ],
};

const allPositionOptions = Array.from(
  new Map(Object.values(positionOptionsByKind).flat().map((option) => [option.value, option])).values(),
);

function selectablePositionValue(position: PlayerPosition) {
  return allPositionOptions.some((option) => option.value === position) ? position : equivalentPositionForKind(position, "futbol7");
}

const legacyPositionMeta: Record<"Porteria" | "Defensa" | "Medio" | "Ataque", { line: PositionLine; label: string; short: string }> = {
  Porteria: { line: "Porteria", label: "Portero", short: "POR" },
  Defensa: { line: "Defensa", label: "Defensa", short: "DEF" },
  Medio: { line: "Medio", label: "Medio", short: "MED" },
  Ataque: { line: "Ataque", label: "Delantero / punta", short: "DEL" },
};

const ratingReviewInterval = 3;
const peerRatingFacetLimit = 1;
const footballSeasonStartMonth = 8;

type RatingFacetConfig = { key: RatingFacet; label: string; short: string };

const fieldRatingFacets: RatingFacetConfig[] = [
  { key: "ritmo", label: "Ritmo", short: "RIT" },
  { key: "tiro", label: "Tiro", short: "TIR" },
  { key: "pase", label: "Pase", short: "PAS" },
  { key: "regate", label: "Regate", short: "REG" },
  { key: "defensa", label: "Defensa", short: "DEF" },
  { key: "fisico", label: "Físico", short: "FÍS" },
];

const goalkeeperRatingFacets: RatingFacetConfig[] = [
  { key: "ritmo", label: "Salidas", short: "SAL" },
  { key: "tiro", label: "Paradas", short: "PAR" },
  { key: "pase", label: "Saque", short: "SAQ" },
  { key: "regate", label: "Reflejos", short: "REF" },
  { key: "defensa", label: "Velocidad", short: "VEL" },
  { key: "fisico", label: "Posición", short: "POS" },
];

const ratingFacets = fieldRatingFacets;

const ratingFacetColors: Record<RatingFacet, string> = {
  ritmo: "#0f766e",
  tiro: "#dc2626",
  pase: "#2563eb",
  regate: "#7c3aed",
  defensa: "#15803d",
  fisico: "#d97706",
};

const assessmentModeOptions: Array<{ label: string; mode: FootballMode }> = [
  { mode: "futsal_5", label: "Fútbol sala" },
  { mode: "football_7", label: "Fútbol 7" },
  { mode: "football_11", label: "Fútbol 11" },
];

const assessmentExperienceOptions: Array<{ id: InitialRatingInput["experienceLevel"]; label: string }> = [
  { id: "barely_played", label: "Estoy empezando" },
  { id: "occasional_pachangas", label: "Pachangas ocasionales" },
  { id: "regular_pachangas", label: "Pachangas habituales" },
  { id: "social_league", label: "Liga social o amateur" },
  { id: "federated_club", label: "Club federado" },
  { id: "national_semipro", label: "Semipro o superior" },
];

const assessmentYearsSinceLevelOptions = [
  { value: 0, label: "Juego ahora" },
  { value: 2, label: "Hace 1-2 años" },
  { value: 5, label: "Hace 3-5 años" },
  { value: 10, label: "Hace 6-10 años" },
  { value: 15, label: "Hace más de 10 años" },
];

const assessmentInitialAnswerOptions: Record<InitialTechnicalQuestionId, Array<{ label: string; value: Exclude<AnswerValue, null> }>> = {
  controlUnderPressure: [
    { value: 1, label: "La pierdo a menudo" },
    { value: 2, label: "Solo con tiempo" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Controlo bajo presión" },
    { value: 5, label: "Destaco controlando" },
  ],
  ballCarrying: [
    { value: 1, label: "Me cuesta conducir" },
    { value: 2, label: "Solo con espacio" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Salgo bien conduciendo" },
    { value: 5, label: "Desbordo con facilidad" },
  ],
  passingExecution: [
    { value: 1, label: "Fallo muchos pases" },
    { value: 2, label: "Pases fáciles" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Paso bien con presión" },
    { value: 5, label: "Creo juego con pases" },
  ],
  decisionMaking: [
    { value: 1, label: "Me precipito" },
    { value: 2, label: "Decido bien con tiempo" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Decido rápido y bien" },
    { value: 5, label: "Leo muy bien el juego" },
  ],
  finishing: [
    { value: 1, label: "Casi no genero peligro" },
    { value: 2, label: "Solo ocasiones claras" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Suelo crear peligro" },
    { value: 5, label: "Marco diferencias arriba" },
  ],
  attackingMovement: [
    { value: 1, label: "Me cuesta ofrecerme" },
    { value: 2, label: "Me muevo poco" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Me desmarco bien" },
    { value: 5, label: "Siempre doy opción" },
  ],
  defensivePositioning: [
    { value: 1, label: "Pierdo la posición" },
    { value: 2, label: "Defiendo a ratos" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Me coloco bien" },
    { value: 5, label: "Anticipo y recupero" },
  ],
  defensiveDuels: [
    { value: 1, label: "Me superan fácil" },
    { value: 2, label: "Me cuesta frenar" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Gano bastantes duelos" },
    { value: 5, label: "Soy muy difícil de superar" },
  ],
  paceComparison: [
    { value: 1, label: "Soy de los más lentos" },
    { value: 2, label: "Me cuesta ganar carreras" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Soy bastante rápido" },
    { value: 5, label: "Soy de los más rápidos" },
  ],
  physicalIntensity: [
    { value: 1, label: "Me falta intensidad" },
    { value: 2, label: "Me cuesta aguantar" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Aguanto bien" },
    { value: 5, label: "Destaco físicamente" },
  ],
};

const assessmentInitialQuestionGroups: Array<{ questionIds: InitialTechnicalQuestionId[]; subtitle: string; title: string }> = [
  { title: "Control", subtitle: "Recepción bajo presión", questionIds: ["controlUnderPressure"] },
  { title: "Conducción", subtitle: "Giro, conducción y regate", questionIds: ["ballCarrying"] },
  { title: "Pase", subtitle: "Ejecución con presión", questionIds: ["passingExecution"] },
  { title: "Decisión", subtitle: "Elegir antes de que cierre el rival", questionIds: ["decisionMaking"] },
  { title: "Finalización", subtitle: "Ocasiones favorables", questionIds: ["finishing"] },
  { title: "Movimiento", subtitle: "Recibir y crear espacio", questionIds: ["attackingMovement"] },
  { title: "Defensa", subtitle: "Posición, anticipación y recuperación", questionIds: ["defensivePositioning"] },
  { title: "Duelos", subtitle: "Frenar al rival", questionIds: ["defensiveDuels"] },
  { title: "Ritmo", subtitle: "Aceleraciones y carreras", questionIds: ["paceComparison"] },
  { title: "Físico", subtitle: "Intensidad durante el partido", questionIds: ["physicalIntensity"] },
];

const assessmentInitialStepCount = 5 + assessmentInitialQuestionGroups.length;
const emptyAssessmentAnswers = Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, null])) as Record<InitialTechnicalQuestionId, AnswerValue>;

const assessmentAttributeFacetMap: Record<AttributeKey, RatingFacet> = {
  pace: "ritmo",
  shooting: "tiro",
  passing: "pase",
  dribbling: "regate",
  defending: "defensa",
  physical: "fisico",
};

const ratingFacetAttributeMap = Object.fromEntries(
  Object.entries(assessmentAttributeFacetMap).map(([attribute, facet]) => [facet, attribute]),
) as Record<RatingFacet, AttributeKey>;

const assessmentPositionToAppPosition: Record<AssessmentPosition, PlayerPosition> = {
  centre_back: "Defensa central",
  full_back: "Lateral derecho",
  defensive_midfielder: "Pivote defensivo",
  central_midfielder: "Mediocentro / pivote",
  attacking_midfielder: "Mediapunta",
  winger: "Extremo derecho",
  striker: "Delantero / punta",
};

const ratingChart = {
  bottom: 118,
  height: 134,
  left: 28,
  right: 12,
  top: 10,
  width: 340,
};

const teamPalette = [
  { name: "Azul", value: "#2157a8" },
  { name: "Rojo", value: "#d93025" },
  { name: "Verde", value: "#16803f" },
  { name: "Amarillo", value: "#f2c94c" },
  { name: "Naranja", value: "#f97316" },
  { name: "Morado", value: "#7c3aed" },
  { name: "Negro", value: "#202820" },
  { name: "Blanco", value: "#f8fafc" },
];

function id() {
  return crypto.randomUUID();
}

function clientOperationMetadata() {
  if (typeof window === "undefined") return {};

  const storageKey = "pachangas-operation-session";
  let sessionId = window.sessionStorage.getItem(storageKey);
  if (!sessionId) {
    sessionId = id();
    window.sessionStorage.setItem(storageKey, sessionId);
  }

  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    sessionId,
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa" : "web",
  };
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function compactUuid(value: string) {
  if (!uuidPattern.test(value)) return value;

  const hex = value.replaceAll("-", "");
  const raw = Array.from({ length: 16 }, (_, index) => String.fromCharCode(Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16))).join("");
  return btoa(raw).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function expandCompactUuid(value: string | null) {
  if (!value) return null;
  if (uuidPattern.test(value)) return value;

  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
    const raw = atob(padded);
    if (raw.length !== 16) return value;

    const hex = Array.from(raw, (char) => char.charCodeAt(0).toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  } catch {
    return value;
  }
}

function incomingSharedLinkFromSearch(search: string): IncomingSharedLink {
  const params = new URLSearchParams(search);
  const hasAdminInvite = Boolean(params.get("a") || params.get("admin"));
  const hasInvite = Boolean(params.get("i") || params.get("invite"));
  const hasMatch = Boolean(params.get("p") || params.get("partido"));

  return {
    hasAdminInvite,
    hasInvite,
    hasMatch,
    teamCode: params.get("equipo"),
  };
}

function nextMatchDate(previousDate: string) {
  const base = new Date(previousDate);
  const next = Number.isNaN(base.getTime()) ? new Date() : base;
  next.setDate(next.getDate() + 7);
  return toDateTimeLocal(next);
}

function toDateTimeLocal(date: Date) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function matchDatePart(value: string) {
  const directDate = value.match(/^\d{4}-\d{2}-\d{2}/)?.[0];
  if (directDate) return directDate;

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? dateInputValue(new Date()) : dateInputValue(parsed);
}

function normalizeMatchTime(value: string) {
  const [, hourText = "21", minuteText = "00"] = value.match(/(?:T|\b)(\d{2}):(\d{2})/) ?? [];
  const hour = Math.max(0, Math.min(23, Number(hourText) || 0));
  const minute = Math.max(0, Math.min(59, Number(minuteText) || 0));
  const roundedMinutes = Math.min(23 * 60 + 50, Math.round((hour * 60 + minute) / 10) * 10);
  const roundedHour = Math.floor(roundedMinutes / 60);
  const roundedMinute = roundedMinutes % 60;
  return `${String(roundedHour).padStart(2, "0")}:${String(roundedMinute).padStart(2, "0")}`;
}

function matchTimePart(value: string) {
  return normalizeMatchTime(value);
}

function combineMatchDateTime(datePart: string, timePart: string) {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(datePart) ? datePart : dateInputValue(new Date());
  return `${date}T${matchTimePart(timePart)}`;
}

function scorePlayer(player: Player) {
  return clampRating(peerAverage(player));
}

function ratingPoints(value: number) {
  return Math.round((Number.isFinite(value) ? value : 0) * 10);
}

function overallScore(score: number) {
  return ratingPoints(clampRating(score));
}

function cardTierClass(score: number) {
  const overall = overallScore(score);
  if (overall <= 64) return "fifa-card-bronze";
  if (overall <= 74) return "fifa-card-silver";
  return "fifa-card-gold";
}

const publicMatchPositionOptions: PublicMatchPosition[] = ["Portero", "Defensa", "Medio", "Ataque"];
const publicMatchRatingPointOptions = [0, 40, 50, 60, 70, 80, 90, 100];

function publicMatchRating(value: unknown, fallback: number) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.max(0, Math.min(10, numeric));
}

function normalizePublicMatchPositions(value: unknown): PublicMatchPosition[] {
  if (!Array.isArray(value)) return [];
  return value.filter((position): position is PublicMatchPosition =>
    publicMatchPositionOptions.includes(position as PublicMatchPosition),
  );
}

function normalizeOpenMatchRequestRow(row: PublicMatchRequestRow): PublicMatchRequest {
  const status: OpenMatchRequestStatus =
    row.status === "accepted" || row.status === "rejected" || row.status === "cancelled" ? row.status : "pending";
  const position = allPositionOptions.some((option) => option.value === row.position)
    ? (row.position as PlayerPosition)
    : "Mediocentro / pivote";

  return {
    avatar: row.avatar ?? undefined,
    avatarOffsetX: clampAvatarOffset(row.avatar_offset_x, 50),
    avatarOffsetY: clampAvatarOffset(row.avatar_offset_y, 0),
    birthDate: normalizeBirthDate(row.birth_date ?? undefined) ?? undefined,
    goalkeeperOnly: Boolean(row.goalkeeper_only),
    id: row.id,
    media: clampRating(Number(row.media) || 5),
    openMatchId: row.open_match_id ?? "",
    playerId: row.player_id ?? undefined,
    position,
    requestedAt: row.requested_at ?? "",
    requesterName: displayName(row.requester_name ?? "Jugador"),
    requesterProfileId: row.requester_profile_id ?? undefined,
    requesterUserId: row.requester_user_id ?? "",
    status,
  };
}

function teamLevelScore(teamPlayers: Player[]) {
  const activePlayers = teamPlayers.filter((player) => !player.inactive);
  if (activePlayers.length === 0) return null;
  return activePlayers.reduce((sum, player) => sum + scorePlayer(player), 0) / activePlayers.length;
}

function clampRating(value: number) {
  return Math.max(1, Math.min(10, Number.isFinite(value) ? value : 5));
}

function clampRatingWithinLimit(value: number, base: number, limit = peerRatingFacetLimit) {
  const cleanBase = clampRating(base);
  return Math.max(clampRating(cleanBase - limit), Math.min(clampRating(cleanBase + limit), clampRating(value)));
}

function assessmentModeFromKind(kind: MatchKind): FootballMode {
  if (kind === "sala") return "futsal_5";
  if (kind === "futbol11") return "football_11";
  return "football_7";
}

function assessmentModeSharesFromKind(kind: MatchKind) {
  const activeMode = assessmentModeFromKind(kind);
  return assessmentModeOptions.map(({ mode }) => ({ mode, percentage: mode === activeMode ? 100 : 0 }));
}

function assessmentSelectedModes(modeShares: InitialRatingInput["modeShares"]) {
  return modeShares.filter((share) => share.percentage > 0).map((share) => share.mode);
}

function assessmentSharesFromSelectedModes(modes: FootballMode[]) {
  if (modes.length === 0) {
    return assessmentModeOptions.map(({ mode }) => ({ mode, percentage: 0 }));
  }
  const base = Math.floor(100 / modes.length);
  let remainder = 100 - base * modes.length;
  return assessmentModeOptions.map(({ mode }) => {
    const active = modes.includes(mode);
    const extra = active && remainder > 0 ? 1 : 0;
    if (extra) remainder -= 1;
    return { mode, percentage: active ? base + extra : 0 };
  });
}

function assessmentPositionFromPlayer(player: Player | undefined, kind: MatchKind): AssessmentPosition {
  if (!player) {
    if (kind === "sala") return "winger";
    return "central_midfielder";
  }
  const position = player.goalkeeperOnly ? rememberedOutfieldPosition(player, kind) : player.position;
  const line = positionMeta(position).line;
  if (line === "Defensa") {
    return position.includes("Lateral") || position === "Carrilero" ? "full_back" : "centre_back";
  }
  if (line === "Ataque") return "striker";
  if (position === "Pivote defensivo" || position === "Cierre") return "defensive_midfielder";
  if (position === "Mediapunta") return "attacking_midfielder";
  if (position.includes("Ala") || position.includes("Extremo")) return "winger";
  return "central_midfielder";
}

function makeAssessmentInitialInput(kind: MatchKind, player?: Player): InitialRatingInput {
  return {
    age: playerAge(player?.birthDate, dateInputValue(new Date())) ?? undefined,
    heightCm: undefined,
    weightKg: undefined,
    primaryPosition: assessmentPositionFromPlayer(player, kind),
    secondaryPositions: [],
    modeShares: assessmentModeSharesFromKind(kind),
    experienceLevel: "regular_pachangas",
    yearsSinceLevel: 0,
    frequency: "weekly",
    answers: { ...emptyAssessmentAnswers },
    calculatedAt: new Date().toISOString(),
  };
}

function assessmentInitialIsComplete(initial: InitialRatingInput) {
  const allTechnicalAnswered = INITIAL_TECHNICAL_QUESTIONS.every((question) => initial.answers[question.id] !== null);
  const modeTotal = initial.modeShares.reduce((total, share) => total + share.percentage, 0);
  return allTechnicalAnswered && Math.round(modeTotal * 100) / 100 === 100;
}

function assessmentInitialStepIsComplete(initial: InitialRatingInput, step: number) {
  if (step === -1) return true;
  if (step === 0) return Math.round(initial.modeShares.reduce((total, share) => total + share.percentage, 0) * 100) / 100 === 100;
  if (step === 1) return Boolean(initial.primaryPosition);
  if (step === 2) return Boolean(initial.experienceLevel);
  if (step === 3) return initial.yearsSinceLevel >= 0;
  if (step === 4) return Boolean(initial.frequency);
  const group = assessmentInitialQuestionGroups[step - 5];
  return group ? group.questionIds.every((questionId) => initial.answers[questionId] !== null) : false;
}

function assessmentFacetsFromRatings(ratings: AttributeRatings) {
  return ATTRIBUTE_KEYS.reduce((next, attribute) => {
    next[assessmentAttributeFacetMap[attribute]] = clampRating(ratings[attribute] / 10);
    return next;
  }, {} as Record<RatingFacet, number>);
}

function assessmentSummaryKindCompleted(player: Player | undefined, kind: PlayerAssessmentKind) {
  if (!player) return false;
  if (player.assessmentSummary?.[kind]?.completedAt) return true;
  return (player.ratingVotes ?? []).some((vote) => vote.source === `${kind}Assessment`);
}

function normalizeAssessmentSummary(value: unknown): PlayerAssessmentSummary | undefined {
  if (!value || typeof value !== "object") return undefined;
  const summary = value as PlayerAssessmentSummary;
  return {
    ...(summary.initial ? { initial: normalizeAssessmentSummaryItem(summary.initial) } : {}),
    ...(summary.advanced ? { advanced: normalizeAssessmentSummaryItem(summary.advanced) } : {}),
  };
}

function normalizeAssessmentSummaryItem(value: unknown): PlayerAssessmentSummaryItem {
  const item = value && typeof value === "object" ? value as PlayerAssessmentSummaryItem : {};
  return {
    completedAt: item.completedAt,
    engineVersion: item.engineVersion,
    facets: normalizeAssessmentFacets(item.facets),
    primaryPosition: item.primaryPosition,
    questionnaireVersion: item.questionnaireVersion,
    rating: Number.isFinite(Number(item.rating)) ? clampRating(Number(item.rating)) : undefined,
    reliability: Number.isFinite(Number(item.reliability)) ? Math.max(0, Math.min(100, Number(item.reliability))) : undefined,
  };
}

function normalizeAssessmentFacets(value: unknown): Partial<Record<RatingFacet, number>> | undefined {
  if (!value || typeof value !== "object") return undefined;
  const facets = value as Partial<Record<RatingFacet, unknown>>;
  const next: Partial<Record<RatingFacet, number>> = {};
  for (const facet of ratingFacets) {
    const numeric = Number(facets[facet.key]);
    if (Number.isFinite(numeric)) next[facet.key] = clampRating(numeric);
  }
  return Object.keys(next).length ? next : undefined;
}

function assessmentAdvancedAnswerOptions(question: AdvancedQuestion): Array<{ label: string; value: Exclude<AnswerValue, null> }> {
  if (question.id.startsWith("RIT") || question.targets.pace && (!question.targets.physical || question.targets.pace >= question.targets.physical)) {
    return [
      { value: 1, label: "Me superan casi siempre" },
      { value: 2, label: "Me cuesta ganar ventaja" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Suelo ganar ventaja" },
      { value: 5, label: "Marco diferencias por velocidad" },
    ];
  }
  if (question.id.startsWith("FIS") || question.targets.physical && (!question.targets.pace || question.targets.physical > question.targets.pace)) {
    return [
      { value: 1, label: "Me cuesta aguantar" },
      { value: 2, label: "Bajo pronto el ritmo" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Aguanto bien" },
      { value: 5, label: "Destaco físicamente" },
    ];
  }
  if (question.module === "shooting" || question.targets.shooting) {
    return [
      { value: 1, label: "Casi no genero peligro" },
      { value: 2, label: "Solo en ocasiones claras" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Suelo generar peligro" },
      { value: 5, label: "Marco diferencias arriba" },
    ];
  }
  if (question.module === "defending" || question.targets.defending && !question.targets.passing) {
    return [
      { value: 1, label: "Me superan fácil" },
      { value: 2, label: "Me cuesta sostenerlo" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Lo hago bastante bien" },
      { value: 5, label: "Soy muy fiable atrás" },
    ];
  }
  if (question.module === "passing" || question.targets.passing && !question.targets.dribbling) {
    return [
      { value: 1, label: "Fallo demasiado" },
      { value: 2, label: "Solo si es fácil" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Lo hago con seguridad" },
      { value: 5, label: "Creo ventaja con eso" },
    ];
  }
  if (question.module === "intelligence") {
    return [
      { value: 1, label: "Me cuesta leerlo" },
      { value: 2, label: "Lo veo tarde" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Lo leo bastante bien" },
      { value: 5, label: "Anticipo lo que va a pasar" },
    ];
  }
  return RESPONSE_OPTIONS.filter((option): option is { label: string; score: number; value: Exclude<AnswerValue, null> } => option.value !== null);
}

function clampAvatarOffset(value: unknown, fallback: number) {
  const numeric = Number(value);
  return Math.max(0, Math.min(100, Number.isFinite(numeric) ? numeric : fallback));
}

function splitMarketList(value?: string) {
  return (value ?? "")
    .split(/[,;\n]/)
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 12);
}

const marketZoneRadiusOptions = [
  { label: "Solo esta población", value: 0 },
  { label: "+5 km", value: 5 },
  { label: "+10 km", value: 10 },
  { label: "+20 km", value: 20 },
  { label: "+30 km", value: 30 },
  { label: "+50 km", value: 50 },
] as const;
const defaultMarketZoneRadiusKm = 0;

const marketWeekdays = [
  { key: "lunes", label: "Lunes" },
  { key: "martes", label: "Martes" },
  { key: "miercoles", label: "Miércoles" },
  { key: "jueves", label: "Jueves" },
  { key: "viernes", label: "Viernes" },
  { key: "sabado", label: "Sábado" },
  { key: "domingo", label: "Domingo" },
] as const;

const marketTimeOptions = Array.from({ length: 48 }, (_, index) => {
  const totalMinutes = index * 30;
  const hour = Math.floor(totalMinutes / 60);
  const minute = totalMinutes % 60;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
});

type MarketAvailabilitySlot = {
  dayKey: (typeof marketWeekdays)[number]["key"];
  enabled: boolean;
  end: string;
  label: string;
  start: string;
};

function normalizeMarketText(value: string) {
  return value
    .toLocaleLowerCase("es-ES")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function marketTimeIndex(value: string) {
  return marketTimeOptions.indexOf(value);
}

function marketTimeRangeIsValid(start: string, end: string) {
  const startIndex = marketTimeIndex(start);
  const endIndex = marketTimeIndex(end);
  return startIndex >= 0 && endIndex >= 0 && endIndex > startIndex;
}

function normalizeMarketEndTime(start: string, end: string) {
  if (marketTimeRangeIsValid(start, end)) return end;
  const startIndex = Math.max(0, marketTimeIndex(start));
  return marketTimeOptions[Math.min(marketTimeOptions.length - 1, startIndex + 2)] ?? "22:00";
}

function marketAvailabilitySlots(value?: string): MarketAvailabilitySlot[] {
  const segments = (value ?? "")
    .split(/[;\n]/)
    .map((item) => item.trim())
    .filter(Boolean);

  return marketWeekdays.map((day) => {
    const normalizedDay = normalizeMarketText(day.label);
    const segment = segments.find((item) => normalizeMarketText(item).includes(normalizedDay));
    const times = segment?.match(/\b\d{2}:\d{2}\b/g) ?? [];
    const startCandidate = times[0] ?? "";
    const endCandidate = times[1] ?? "";
    const start = marketTimeOptions.includes(startCandidate) ? startCandidate : "20:00";
    const end = marketTimeOptions.includes(endCandidate) ? endCandidate : "22:00";

    return {
      dayKey: day.key,
      enabled: Boolean(segment),
      end: normalizeMarketEndTime(start, end),
      label: day.label,
      start,
    };
  });
}

function serializeMarketAvailability(slots: MarketAvailabilitySlot[]) {
  return slots
    .filter((slot) => slot.enabled && marketTimeRangeIsValid(slot.start, slot.end))
    .map((slot) => `${slot.label} ${slot.start}-${slot.end}`)
    .join("; ");
}

function updateMarketAvailabilityText(
  value: string | undefined,
  dayKey: MarketAvailabilitySlot["dayKey"],
  patch: Partial<Pick<MarketAvailabilitySlot, "enabled" | "end" | "start">>,
) {
  const slots = marketAvailabilitySlots(value).map((slot) => {
    if (slot.dayKey !== dayKey) return slot;
    const nextStart = patch.start ?? slot.start;
    const nextEnd = normalizeMarketEndTime(nextStart, patch.end ?? slot.end);
    return {
      ...slot,
      ...patch,
      end: nextEnd,
      start: nextStart,
    };
  });

  return serializeMarketAvailability(slots);
}

function marketAvailabilityIsComplete(value?: string) {
  return marketAvailabilitySlots(value).some((slot) => slot.enabled && marketTimeRangeIsValid(slot.start, slot.end));
}

function marketZoneLabelFromPlace(place: Pick<VenuePlace, "city" | "name" | "province">) {
  const main = place.city || place.name;
  const province = place.province && normalizeMarketText(place.province) !== normalizeMarketText(main) ? place.province : "";
  return [main, province].filter(Boolean).join(", ");
}

function normalizeMarketZoneRadius(value: unknown) {
  const radius = Number(value);
  const option = marketZoneRadiusOptions.find((item) => item.value === radius);
  return option ? option.value : defaultMarketZoneRadiusKm;
}

function normalizeMarketZone(zone: Partial<MarketZone> | null | undefined): MarketZone | null {
  const placeId = typeof zone?.placeId === "string" ? zone.placeId.trim() : "";
  const name = typeof zone?.name === "string" ? zone.name.trim() : "";
  if (!placeId || !name) return null;

  return {
    address: zone?.address || undefined,
    city: zone?.city || undefined,
    country: zone?.country || undefined,
    lat: Number.isFinite(Number(zone?.lat)) ? Number(zone?.lat) : undefined,
    lng: Number.isFinite(Number(zone?.lng)) ? Number(zone?.lng) : undefined,
    name,
    placeId,
    province: zone?.province || undefined,
    radiusKm: normalizeMarketZoneRadius(zone?.radiusKm),
  };
}

function normalizeMarketZonesGeo(value: unknown): MarketZone[] {
  const rawZones = Array.isArray(value) ? value : [];
  const seen = new Set<string>();
  const zones: MarketZone[] = [];

  rawZones.forEach((zone) => {
    const normalized = normalizeMarketZone(zone as Partial<MarketZone>);
    if (!normalized || seen.has(normalized.placeId)) return;
    seen.add(normalized.placeId);
    zones.push(normalized);
  });

  return zones.slice(0, 12);
}

function marketZoneTextFromGeo(zones: MarketZone[]) {
  return zones.map((zone) => marketZoneLabelFromPlace(zone)).filter(Boolean).join(", ");
}

function marketZoneFromPlace(place: VenuePlace, radiusKm = defaultMarketZoneRadiusKm): MarketZone | null {
  const normalized = normalizeMarketZone({
    ...place,
    name: place.city || place.name,
    radiusKm,
  });
  return normalized;
}

function appendMarketZoneGeo(value: MarketZone[] | undefined, place: VenuePlace, radiusKm = defaultMarketZoneRadiusKm) {
  const zones = normalizeMarketZonesGeo(value);
  const nextZone = marketZoneFromPlace(place, radiusKm);
  if (!nextZone) return zones;
  const nextZones = zones.filter((zone) => zone.placeId !== nextZone.placeId);
  return [...nextZones, nextZone].slice(0, 12);
}

function updateMarketZoneRadius(value: MarketZone[] | undefined, placeId: string, radiusKm: number) {
  return normalizeMarketZonesGeo(value).map((zone) =>
    zone.placeId === placeId ? { ...zone, radiusKm: normalizeMarketZoneRadius(radiusKm) } : zone,
  );
}

function removeMarketZoneGeo(value: MarketZone[] | undefined, placeId: string) {
  return normalizeMarketZonesGeo(value).filter((zone) => zone.placeId !== placeId);
}

function playerMarketProfileComplete(player: Player) {
  if (!player.marketEnabled) return true;
  return normalizeMarketZonesGeo(player.marketZonesGeo).length > 0 && marketAvailabilityIsComplete(player.marketAvailability);
}

function marketModalitiesForPlayer(player: Player) {
  return (player.marketModalities?.length ? player.marketModalities : (Object.keys(matchKinds) as MatchKind[])).filter((kind) => Boolean(matchKinds[kind]));
}

function avatarImageStyle(player: Pick<Player, "avatarOffsetX" | "avatarOffsetY">): CSSProperties {
  return {
    objectFit: "cover",
    objectPosition: `${clampAvatarOffset(player.avatarOffsetX, 50)}% ${clampAvatarOffset(player.avatarOffsetY, 0)}%`,
  };
}

async function withTimeout<T>(promise: Promise<T>, ms: number, message: string) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function displayName(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .map((word) => word.charAt(0).toLocaleUpperCase("es-ES") + word.slice(1).toLocaleLowerCase("es-ES"))
    .join(" ");
}

function nameInitials(name: string) {
  const words = displayName(name).split(/\s+/).filter(Boolean);
  if (words.length === 0) return "PI";
  const first = words[0]?.charAt(0) ?? "";
  const lastWord = words[words.length - 1] ?? "";
  const second = words.length > 1 ? lastWord.charAt(0) : words[0]?.charAt(1) ?? "";
  return `${first}${second}`.toLocaleUpperCase("es-ES");
}

function memberRoleLabel(role: MemberRole | null | undefined) {
  if (role === "owner") return "Owner / Admin";
  if (role === "admin") return "Admin";
  if (role === "player") return "Jugador";
  return "-";
}

function normalizeBillingStatus(status: unknown): BillingStatus {
  if (
    status === "active" ||
    status === "trialing" ||
    status === "past_due" ||
    status === "canceled" ||
    status === "unpaid" ||
    status === "incomplete"
  ) {
    return status;
  }

  return "trial";
}

function normalizeBillingInterval(interval: unknown): BillingInterval | null {
  return interval === "month" || interval === "year" ? interval : null;
}

function billingDateIsActive(date: string | null | undefined) {
  if (!date) return true;
  const parsed = new Date(date);
  return Number.isNaN(parsed.getTime()) || parsed.getTime() >= Date.now();
}

function teamBillingIsActive(team: RemoteTeam | null | undefined) {
  return Boolean(
    team &&
      (team.billingStatus === "active" || team.billingStatus === "trialing") &&
      billingDateIsActive(team.stripeCurrentPeriodEnd),
  );
}

function billingStatusLabel(team: RemoteTeam | null | undefined) {
  if (teamBillingIsActive(team)) return "Suscripción activa";
  if (team?.billingStatus === "past_due") return "Pago pendiente";
  if (team?.billingStatus === "incomplete") return "Pago sin completar";
  if (team?.billingStatus === "unpaid") return "Suscripción impagada";
  if (team?.billingStatus === "canceled") return "Suscripción cancelada";
  return "Prueba gratuita";
}

function billingPeriodLabel(interval: BillingInterval | null | undefined) {
  return interval === "month" ? "mensual" : interval === "year" ? "anual" : "sin plan";
}

function billingPatchFromRecord(record: Record<string, unknown>): Partial<RemoteTeam> {
  return {
    billingInterval: normalizeBillingInterval(record.billing_interval),
    billingStatus: normalizeBillingStatus(record.billing_status),
    billingTrialFinalizedMatches: Math.max(0, Math.floor(Number(record.billing_trial_finalized_matches) || 0)),
    stripeCustomerId: record.stripe_customer_id ? String(record.stripe_customer_id) : null,
    stripeCurrentPeriodEnd: record.stripe_current_period_end ? String(record.stripe_current_period_end) : null,
    stripePriceId: record.stripe_price_id ? String(record.stripe_price_id) : null,
    stripeSubscriptionId: record.stripe_subscription_id ? String(record.stripe_subscription_id) : null,
  };
}

function groupOptionLabel(team: RemoteTeam) {
  return `${team.name} · ${memberRoleLabel(team.role)}`;
}

function monthLabel(date: string) {
  const label = new Date(date).toLocaleDateString("es-ES", { month: "long", year: "numeric" });
  return label.charAt(0).toLocaleUpperCase("es-ES") + label.slice(1);
}

function seasonKey(date: string | Date) {
  const parsed = date instanceof Date ? new Date(date) : new Date(date);
  if (Number.isNaN(parsed.getTime())) return "Sin temporada";
  const year = parsed.getFullYear();
  const startYear = parsed.getMonth() >= footballSeasonStartMonth ? year : year - 1;
  return `${startYear}-${startYear + 1}`;
}

function matchSeason(match: Pick<Match, "date" | "season">) {
  return match.season || seasonKey(match.date);
}

function seasonStartYear(key: string) {
  const start = Number(key.split("-")[0]);
  return Number.isFinite(start) ? start : 0;
}

function joinedAtLabel(date?: string) {
  if (!date) return "";

  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "";

  return parsed.toLocaleString("es-ES", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function ratingVoteDateLabel(date: string) {
  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "";

  return parsed.toLocaleDateString("es-ES", {
    day: "2-digit",
    month: "short",
  });
}

function matchSummaryDate(date: string) {
  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "Fecha por confirmar";

  return parsed.toLocaleString("es-ES", {
    weekday: "long",
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function matchDayLabel(date: string) {
  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "Día por confirmar";

  return parsed.toLocaleDateString("es-ES", { weekday: "short" });
}

function matchTimeLabel(date: string) {
  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "Hora por confirmar";

  return parsed.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
}

function matchTitleWithoutTrailingTime(title: string) {
  return title.replace(/\s+\d{1,2}:\d{2}\s*$/, "").trim();
}

function weatherVisualKey(weather: MatchWeather | null, status: "error" | "idle" | "loading" | "ready" | "unavailable") {
  if (status === "loading") return "loading";
  if (status === "error") return "storm";
  if (!weather) return "cloud";

  const raw = `${weather.conditionType} ${weather.condition}`.toLocaleLowerCase("es-ES");
  if (/thunder|storm|tormenta/.test(raw)) return "storm";
  if (/snow|sleet|ice|nieve|granizo/.test(raw)) return "snow";
  if (/rain|shower|drizzle|lluv|chubasco/.test(raw)) return "rain";
  if (/fog|mist|haze|niebla|bruma/.test(raw)) return "fog";
  if ((weather.windKmh ?? 0) >= 30 || /wind|viento/.test(raw)) return "wind";
  if (/partly|mostly|cloud|overcast|nube|cubierto|nublado/.test(raw)) return raw.includes("partly") ? "partly" : "cloud";
  return "sun";
}

function WeatherIcon({ status, weather }: { status: "error" | "idle" | "loading" | "ready" | "unavailable"; weather: MatchWeather | null }) {
  const key = weatherVisualKey(weather, status);

  return (
    <span className={`weather-icon weather-icon-${key}`} aria-hidden="true">
      <svg viewBox="0 0 48 48" role="img">
        {key === "sun" ? (
          <>
            <circle cx="24" cy="24" r="8" />
            <path d="M24 5v7M24 36v7M5 24h7M36 24h7M10 10l5 5M33 33l5 5M38 10l-5 5M15 33l-5 5" />
          </>
        ) : null}
        {key === "partly" ? (
          <>
            <circle cx="18" cy="18" r="6" />
            <path d="M18 5v5M6 18h5M9 9l4 4M28 9l-4 4" />
            <path d="M17 34h19a7 7 0 0 0 1-14 10 10 0 0 0-19-2 8 8 0 0 0-1 16Z" />
          </>
        ) : null}
        {key === "cloud" || key === "loading" ? (
          <path d="M13 34h22a8 8 0 0 0 1-16 11 11 0 0 0-21-2 9 9 0 0 0-2 18Z" />
        ) : null}
        {key === "rain" ? (
          <>
            <path d="M13 27h22a8 8 0 0 0 1-16 11 11 0 0 0-21-2 9 9 0 0 0-2 18Z" />
            <path d="M18 33l-2 5M26 33l-2 5M34 33l-2 5" />
          </>
        ) : null}
        {key === "storm" ? (
          <>
            <path d="M13 27h22a8 8 0 0 0 1-16 11 11 0 0 0-21-2 9 9 0 0 0-2 18Z" />
            <path d="M25 30l-5 8h7l-3 6" />
          </>
        ) : null}
        {key === "snow" ? (
          <>
            <path d="M13 26h22a8 8 0 0 0 1-16 11 11 0 0 0-21-2 9 9 0 0 0-2 18Z" />
            <path d="M18 34h.01M26 36h.01M34 34h.01M22 41h.01M30 41h.01" />
          </>
        ) : null}
        {key === "fog" ? (
          <>
            <path d="M13 23h22a8 8 0 0 0 1-16 11 11 0 0 0-21-2 9 9 0 0 0-2 18Z" />
            <path d="M10 31h28M14 37h20M9 42h30" />
          </>
        ) : null}
        {key === "wind" ? (
          <>
            <path d="M8 18h22a5 5 0 1 0-5-5" />
            <path d="M8 27h30a5 5 0 1 1-5 5" />
            <path d="M8 36h16" />
          </>
        ) : null}
      </svg>
    </span>
  );
}

function WeatherMetricIcon({ kind }: { kind: "feels" | "humidity" | "rain" | "wind" }) {
  return (
    <i className={`weather-metric-icon weather-metric-icon-${kind}`} aria-hidden="true">
      <svg viewBox="0 0 24 24">
        {kind === "feels" ? (
          <>
            <path d="M14 14.8V5a4 4 0 0 0-8 0v9.8a6 6 0 1 0 8 0Z" />
            <path d="M10 6v9" />
          </>
        ) : null}
        {kind === "rain" ? (
          <>
            <path d="M6 9.5h10a4 4 0 0 0 .5-8 5.5 5.5 0 0 0-10.3 1.4A4.5 4.5 0 0 0 6 9.5Z" />
            <path d="M7 14l-1.4 3.2M12 14l-1.4 3.2M17 14l-1.4 3.2" />
          </>
        ) : null}
        {kind === "wind" ? (
          <>
            <path d="M3 8h12a3 3 0 1 0-3-3" />
            <path d="M3 14h16a3 3 0 1 1-3 3" />
          </>
        ) : null}
        {kind === "humidity" ? (
          <path d="M12 3s6 6.2 6 11a6 6 0 0 1-12 0c0-4.8 6-11 6-11Z" />
        ) : null}
      </svg>
    </i>
  );
}

function dateInputValue(date: Date) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function requestNativeInputPicker(input: HTMLInputElement) {
  if (input.disabled) return;
  try {
    (input as HTMLInputElement & { showPicker?: () => void }).showPicker?.();
  } catch {
    input.focus();
  }
}

function normalizeBirthDate(value?: string) {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return "";
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(year, month - 1, day);
  if (parsed.getFullYear() !== year || parsed.getMonth() !== month - 1 || parsed.getDate() !== day) return "";
  return value;
}

function playerAge(birthDate?: string, todayValue = dateInputValue(new Date())) {
  const normalizedBirthDate = normalizeBirthDate(birthDate);
  const normalizedToday = normalizeBirthDate(todayValue);
  if (!normalizedBirthDate || !normalizedToday) return null;

  const [birthYear, birthMonth, birthDay] = normalizedBirthDate.split("-").map(Number);
  const [todayYear, todayMonth, todayDay] = normalizedToday.split("-").map(Number);
  let age = todayYear - birthYear;
  if (todayMonth < birthMonth || (todayMonth === birthMonth && todayDay < birthDay)) age -= 1;
  return age >= 0 && age <= 120 ? age : null;
}

function playerDisplayName(player: Player) {
  return displayName(player.name);
}

function normalizeSiteSettings(settings?: Partial<SiteSettings>): SiteSettings {
  const monthlyAmount = Number(settings?.subscriptionContributionMonthlyAmount);
  const yearlyAmount = Number(settings?.subscriptionContributionYearlyAmount);

  return {
    ...defaultSiteSettings,
    ...settings,
    subscriptionContributionEnabled: Boolean(settings?.subscriptionContributionEnabled),
    subscriptionContributionMonthlyAmount: Number.isFinite(monthlyAmount) && monthlyAmount >= 0 ? monthlyAmount : defaultSiteSettings.subscriptionContributionMonthlyAmount,
    subscriptionContributionPeriod: settings?.subscriptionContributionPeriod === "month" ? "month" : "year",
    subscriptionContributionYearlyAmount: Number.isFinite(yearlyAmount) && yearlyAmount >= 0 ? yearlyAmount : defaultSiteSettings.subscriptionContributionYearlyAmount,
    teamAColor: settings?.teamAColor ?? defaultSiteSettings.teamAColor,
    teamBColor: settings?.teamBColor ?? defaultSiteSettings.teamBColor,
  };
}

function normalizeVenue(venue: Venue): Venue {
  return {
    ...venue,
    address: venue.address || undefined,
    city: venue.city || undefined,
    country: venue.country || undefined,
    defaultCost: Number(venue.defaultCost) || 0,
    kind: venue.kind && matchKinds[venue.kind] ? venue.kind : undefined,
    lat: Number.isFinite(Number(venue.lat)) ? Number(venue.lat) : undefined,
    lng: Number.isFinite(Number(venue.lng)) ? Number(venue.lng) : undefined,
    placeId: venue.placeId || undefined,
    province: venue.province || undefined,
  };
}

function normalizePayload(payload?: Partial<AppPayload>): AppPayload {
  const fallback = defaultPayload();
  const venues = (payload?.venues ? payload.venues : fallback.venues).map(normalizeVenue);
  const rawMatches = payload?.matches ? payload.matches : fallback.matches;
  const matches = rawMatches.length
    ? rawMatches.map((match) => ({
        ...match,
        venueId: match.venueId ?? venues.find((venue) => venue.name === match.place)?.id,
        fieldCost: match.fieldCost ?? (match.price ? match.price * Math.max(match.targetPlayers, 1) : 0),
        configured: match.configured ?? Boolean(match.closed || match.scoreA !== undefined || match.players?.length || match.venueId),
        lineupClosed: match.lineupClosed ?? false,
        lineupSlots: cleanLineupSlots(match.lineupSlots, match.teamA ?? [], match.teamB ?? []),
        publicGuestsPay: match.publicGuestsPay ?? true,
        publicMaxRating: publicMatchRating(match.publicMaxRating, 10),
        publicMinRating: publicMatchRating(match.publicMinRating, 0),
        publicOpen: Boolean(match.publicOpen),
        publicOpenSlots: Math.max(1, Math.floor(Number(match.publicOpenSlots) || 1)),
        publicPositions: normalizePublicMatchPositions(match.publicPositions),
        publicRequiresApproval: match.publicRequiresApproval ?? true,
        reservesAttend: match.reservesAttend ?? false,
        reserveLimit: Math.max(0, Math.floor(match.reserveLimit ?? 0)),
        season: match.season || seasonKey(match.date),
      }))
    : [starterMatch()];
  const players = (payload?.players ? payload.players : fallback.players).map((player) => {
    const position = player.position ?? "Mediocentro / pivote";
    const outfieldPosition = player.outfieldPosition && !isGoalkeeperPosition(player.outfieldPosition)
      ? player.outfieldPosition
      : !isGoalkeeperPosition(position)
        ? position
        : "Mediocentro / pivote";

    return {
      ...player,
      assessmentSummary: normalizeAssessmentSummary(player.assessmentSummary),
      avatarOffsetX: player.avatar ? clampAvatarOffset(player.avatarOffsetX, 50) : undefined,
      avatarOffsetY: player.avatar ? clampAvatarOffset(player.avatarOffsetY, 0) : undefined,
      birthDate: normalizeBirthDate(player.birthDate),
      globalPlayerProfileId: player.globalPlayerProfileId || undefined,
      importedRating: player.importedRating ? clampRating(Number(player.importedRating)) : undefined,
      importedRatingAt: player.importedRatingAt || undefined,
      importedRatingFromGroup: player.importedRatingFromGroup || undefined,
      injured: Boolean(player.injured),
      inactive: Boolean(player.inactive),
      marketAvailability: player.marketAvailability || "",
      marketBio: player.marketBio || "",
      marketEnabled: Boolean(player.marketEnabled),
      marketModalities: (player.marketModalities ?? []).filter((kind): kind is MatchKind => Boolean(matchKinds[kind])),
      marketOpenToGroup: player.marketOpenToGroup ?? true,
      marketOpenToGuest: player.marketOpenToGuest ?? true,
      marketZones: marketZoneTextFromGeo(normalizeMarketZonesGeo(player.marketZonesGeo)),
      marketZonesGeo: normalizeMarketZonesGeo(player.marketZonesGeo),
      outfieldPosition,
      position,
      rating: clampRating(Number(player.rating ?? 5)),
      ratingVotes: normalizeRatingVotes(player.ratingVotes),
    };
  });

  return {
    activeMatchId: payload?.activeMatchId && matches.some((match) => match.id === payload.activeMatchId) ? payload.activeMatchId : matches[0].id,
    matches,
    players,
    siteSettings: normalizeSiteSettings(payload?.siteSettings),
    venues,
  };
}

function serializePayload(payload: AppPayload) {
  return JSON.stringify(payload);
}

type LocalPayloadCacheSource = "local-draft" | "server-cache";

type LocalPayloadCache = {
  cachedAt: string;
  kind: "pachanga-iq-cache";
  payload: Partial<AppPayload>;
  source: LocalPayloadCacheSource;
};

function serializeLocalPayloadCache(payload: AppPayload, source: LocalPayloadCacheSource) {
  return JSON.stringify({
    cachedAt: new Date().toISOString(),
    kind: "pachanga-iq-cache",
    payload,
    source,
  } satisfies LocalPayloadCache);
}

function parseLocalPayloadCache(value: string) {
  const parsed = JSON.parse(value) as Partial<AppPayload> | Partial<LocalPayloadCache>;
  if (
    parsed &&
    typeof parsed === "object" &&
    "kind" in parsed &&
    parsed.kind === "pachanga-iq-cache" &&
    "payload" in parsed
  ) {
    return parsed.payload as Partial<AppPayload>;
  }

  return parsed as Partial<AppPayload>;
}

function normalizeRatingVotes(votes?: RatingVote[]) {
  return (votes ?? [])
    .map((vote) => {
      const facets = ratingFacets.reduce((next, facet) => {
        next[facet.key] = clampRating(Number(vote.facets?.[facet.key] ?? 5));
        return next;
      }, {} as Record<RatingFacet, number>);

      return {
        id: vote.id || id(),
        voterId: vote.voterId || "legacy",
        voterName: vote.voterName,
        ratingRole: vote.ratingRole === "field" || vote.ratingRole === "goalkeeper" ? vote.ratingRole : undefined,
        source: vote.source === "initialAssessment" || vote.source === "advancedAssessment" ? vote.source : undefined,
        matchCount: Math.max(0, Math.floor(Number(vote.matchCount) || 0)),
        createdAt: vote.createdAt || new Date().toISOString(),
        facets,
      };
    })
    .filter((vote) => vote.voterId);
}

function peerAverage(player: Player) {
  const facets = ratingFacetsForPlayer(player);
  const facetScores = facets.map((facet) => facetAverage(player, facet.key));
  if (facetScores.length > 0) return facetScores.reduce((sum, rating) => sum + rating, 0) / facetScores.length;
  if (player.ratings?.length) return player.ratings.reduce((sum, rating) => sum + rating, 0) / player.ratings.length;
  return player.rating;
}

function groupRatingVoteCount(player: Player) {
  return (player.ratingVotes ?? []).filter((vote) => !vote.source).length + (player.ratings?.length ?? 0);
}

function hasGroupRatingData(player: Player) {
  return groupRatingVoteCount(player) > 0;
}

function playerRatingSource(player: Player) {
  if (hasGroupRatingData(player)) return "del grupo";
  if (assessmentSummaryKindCompleted(player, "advanced")) return "test avanzado";
  if (assessmentSummaryKindCompleted(player, "initial")) return "test inicial";
  if (player.importedRating) return "importada";
  return "";
}

function ratingSeriesOffset(index: number, total: number) {
  if (total <= 1) return 0;
  const spread = Math.min(10, total * 1.7);
  return ((index / (total - 1)) - 0.5) * spread;
}

function ratingChartX(index: number, total: number, seriesIndex = 0, seriesTotal = 1) {
  const usableWidth = ratingChart.width - ratingChart.left - ratingChart.right;
  const x = total <= 1 ? ratingChart.left + usableWidth / 2 : ratingChart.left + (usableWidth * index) / (total - 1);
  return Math.max(ratingChart.left, Math.min(ratingChart.width - ratingChart.right, x + ratingSeriesOffset(seriesIndex, seriesTotal)));
}

function ratingChartY(value: number) {
  const usableHeight = ratingChart.bottom - ratingChart.top;
  return ratingChart.top + ((10 - clampRating(value)) / 9) * usableHeight;
}

function ratingLinePath(votes: RatingVote[], facet: RatingFacet, seriesIndex = 0, seriesTotal = 1) {
  return votes
    .map((vote, index) => {
      const x = ratingChartX(index, votes.length, seriesIndex, seriesTotal);
      const y = ratingChartY(vote.facets[facet] ?? 5);
      return `${index === 0 ? "M" : "L"} ${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(" ");
}

function baseFacetRating(player: Player) {
  if (player.ratings?.length) return averageRatingValues(player.ratings);
  return player.rating;
}

function boundedFacetVoteValues(player: Player, facet: RatingFacet) {
  const values: number[] = [];
  let baseline = baseFacetRating(player);

  for (const vote of ratingHistory(player, ratingRoleForPlayer(player))) {
    const boundedValue = clampRatingWithinLimit(vote.facets?.[facet] ?? baseline, baseline);
    values.push(boundedValue);
    baseline = averageRatingValues(values);
  }

  return values;
}

function facetAverage(player: Player, facet: RatingFacet) {
  const facetVotes = boundedFacetVoteValues(player, facet);
  if (facetVotes.length > 0) return facetVotes.reduce((sum, rating) => sum + rating, 0) / facetVotes.length;
  if (player.ratings?.length) return player.ratings.reduce((sum, rating) => sum + rating, 0) / player.ratings.length;
  return player.rating;
}

function currentPeerFacetBaseline(player: Player, facet: RatingFacet) {
  return facetAverage(player, facet);
}

function cappedDelta(value: number, limit: number) {
  return Math.max(-limit, Math.min(limit, value));
}

function teamSideForPlayer(match: Match, playerId: string) {
  if (match.teamA?.includes(playerId)) return "A" as const;
  if (match.teamB?.includes(playerId)) return "B" as const;
  return undefined;
}

function teamIdsForSide(match: Match, side: "A" | "B") {
  return side === "A" ? match.teamA ?? [] : match.teamB ?? [];
}

function teamScoreForSide(match: Match, side: "A" | "B") {
  return side === "A" ? match.scoreA ?? 0 : match.scoreB ?? 0;
}

function matchGoalsForPlayer(match: Match, playerId: string) {
  return match.scorers?.find((entry) => entry.playerId === playerId)?.goals ?? 0;
}

function matchImpactForPlayer(match: Match, player: Player, side: "A" | "B", playersById: Map<string, Player>): MatchRatingImpact {
  const goalsFor = teamScoreForSide(match, side);
  const goalsAgainst = teamScoreForSide(match, side === "A" ? "B" : "A");
  const diff = goalsFor - goalsAgainst;
  const absDiff = Math.abs(diff);
  const playerGoals = matchGoalsForPlayer(match, player.id);
  const teamHasFixedKeeper = teamIdsForSide(match, side).some((playerId) => playersById.get(playerId)?.goalkeeperOnly);
  const line = playerPosition(player);
  const isKeeper = line === "Porteria";
  const isDefensive = isKeeper || line === "Defensa";
  const notes: string[] = [];
  let delta = 0;

  if (diff > 0) {
    delta += 0.08 + Math.min(0.08, diff * 0.02);
    notes.push(absDiff >= 4 ? "victoria amplia" : "victoria");
  } else if (diff < 0) {
    const closeLoss = absDiff <= 1;
    delta -= closeLoss ? 0.03 : 0.05 + Math.min(0.12, absDiff * 0.025);
    if (goalsFor >= 2) delta += 0.02;
    if (goalsFor >= 4) delta += 0.02;
    notes.push(closeLoss ? "derrota ajustada" : absDiff >= 4 ? "derrota amplia" : "derrota");
  } else {
    if (goalsFor > 0) delta += 0.02;
    notes.push("empate");
  }

  if (playerGoals > 0) {
    delta += Math.min(0.14, playerGoals * 0.045);
    notes.push(`${playerGoals} ${playerGoals === 1 ? "gol" : "goles"}`);
  }

  if (isDefensive) {
    if (goalsAgainst === 0) {
      delta += isKeeper ? (player.goalkeeperOnly ? 0.14 : 0.1) : teamHasFixedKeeper ? 0.08 : 0.06;
      notes.push("portería a cero");
    } else if (goalsAgainst === 1) {
      delta += isKeeper ? (player.goalkeeperOnly ? 0.08 : 0.06) : teamHasFixedKeeper ? 0.045 : 0.03;
      notes.push("pocos goles encajados");
    } else if (goalsAgainst === 2 && diff >= 0) {
      delta += isKeeper ? 0.03 : 0.02;
    }

    if (goalsAgainst >= 4) {
      delta -= isKeeper ? (player.goalkeeperOnly ? 0.08 : 0.06) : 0.05;
      notes.push("muchos goles encajados");
    }
    if (goalsAgainst >= 6) delta -= isKeeper ? 0.04 : 0.03;
  }

  return {
    delta: cappedDelta(delta, 0.24),
    notes,
  };
}

function matchFormRatingForPlayer(match: Match, player: Player, side: "A" | "B", playersById: Map<string, Player>) {
  const impact = matchImpactForPlayer(match, player, side, playersById);
  return {
    notes: impact.notes,
    rating: clampRating(6.2 + impact.delta * 10),
  };
}

function playerReliability(player: Player) {
  return Math.max(70, Math.min(100, Math.round(100 - Math.max(0, player.lateCancels || 0) * 7)));
}

function visibleFormPercent(form: PlayerFormState) {
  return Math.max(0, Math.min(100, form.percent));
}

function playerFormState(player: Player, matches: Match[], playersById: Map<string, Player>): PlayerFormState {
  if (player.inactive) {
    return {
      balanceScore: clampRating(peerAverage(player) * 0.7),
      hasData: true,
      label: "Fuera del grupo",
      notes: ["no cuenta para nuevos partidos"],
      percent: 70,
      recentAverage: null,
      reliability: playerReliability(player),
      status: "inactive",
    };
  }

  const finalizedMatches = matches
    .filter((match) => match.scoreA !== undefined && match.scoreB !== undefined)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
  const absenceStreak = consecutiveAbsenceStreak(finalizedMatches, player.id);
  const playedRatings = finalizedMatches
    .map((match) => {
      const side = teamSideForPlayer(match, player.id);
      if (!side || !matchAttendingIds(match).has(player.id)) return null;
      return matchFormRatingForPlayer(match, player, side, playersById);
    })
    .filter((item): item is { notes: string[]; rating: number } => Boolean(item))
    .slice(-5);
  const recentAverage = playedRatings.length
    ? playedRatings.reduce((sum, item) => sum + item.rating, 0) / playedRatings.length
    : null;
  const hasData = playedRatings.length > 0;
  const recentNotes = playedRatings.flatMap((item) => item.notes).filter((note, index, notes) => notes.indexOf(note) === index).slice(-3);
  const performanceBoost = recentAverage === null ? 0 : (recentAverage - 6.2) * 5.5;
  const absencePenalty = player.injured
    ? Math.min(8, absenceStreak * 1.6)
    : absenceStreak <= 1
      ? 0
      : Math.min(18, (absenceStreak - 1) * 3.5);
  const reliabilityPenalty = Math.max(0, 100 - playerReliability(player)) * 0.12;
  const rawPercent = 100 + performanceBoost - absencePenalty - reliabilityPenalty;
  const percent = Math.round(Math.max(player.injured ? 88 : 78, Math.min(110, rawPercent)));
  const balanceScore = clampRating(peerAverage(player) * (percent / 100));
  let status: PlayerFormState["status"] = "normal";
  let label: PlayerFormState["label"] = "Normal";

  if (player.injured) {
    status = "injured";
    label = "En recuperación";
  } else if (absenceStreak >= 4) {
    status = "returning";
    label = null;
  } else if (percent >= 106) {
    status = "excellent";
    label = "Excelente";
  } else if (percent >= 101) {
    status = "good";
    label = "En ritmo";
  } else if (percent <= 92) {
    status = "low";
    label = "Sin ritmo";
  }

  const notes = [
    recentAverage === null ? "sin partidos recientes" : `últimos ${playedRatings.length} PJ: ${overallScore(recentAverage)}`,
    absenceStreak > 0 ? `${absenceStreak} sin venir` : "",
    player.injured ? "lesión suave" : "",
    player.lateCancels > 0 ? `fiabilidad ${playerReliability(player)}%` : "",
    ...recentNotes,
  ].filter(Boolean);

  return {
    balanceScore,
    hasData,
    label,
    notes,
    percent,
    recentAverage,
    reliability: playerReliability(player),
    status,
  };
}

function playerFormStates(matches: Match[], players: Player[]) {
  const playersById = new Map(players.map((player) => [player.id, player]));
  return new Map(players.map((player) => [player.id, playerFormState(player, matches, playersById)]));
}

function ratingHistory(player: Player, role?: RatingRole) {
  const votes = role ? ratingVotesForRole(player, role) : (player.ratingVotes ?? []);
  return [...votes].sort((a, b) => a.matchCount - b.matchCount || a.createdAt.localeCompare(b.createdAt));
}

function averageRatingValues(values: number[]) {
  const cleanValues = values.map((value) => clampRating(value)).filter((value) => Number.isFinite(value));
  return cleanValues.length > 0 ? cleanValues.reduce((sum, value) => sum + value, 0) / cleanValues.length : 5;
}

function ratingAverageFromVotes(player: Player, votes: RatingVote[]) {
  return peerAverage({ ...player, ratingVotes: votes });
}

function playerRatingTrend(player: Player): RatingTrend | null {
  const votes = ratingHistory(player, ratingRoleForPlayer(player));
  const legacyRatings = player.ratings ?? [];
  const current = overallScore(peerAverage(player));
  let previous: number | null = null;

  if (votes.length > 0) {
    const previousVotes = votes.slice(0, -1);
    previous = previousVotes.length > 0
      ? overallScore(ratingAverageFromVotes(player, previousVotes))
      : overallScore(legacyRatings.length > 0 ? averageRatingValues(legacyRatings) : player.rating);
  } else if (legacyRatings.length > 1) {
    previous = overallScore(averageRatingValues(legacyRatings.slice(0, -1)));
  }

  if (previous === null) return null;

  return {
    current,
    direction: current > previous ? "up" : current < previous ? "down" : "flat",
    previous,
  };
}

function ratingTrendText(trend: RatingTrend) {
  if (trend.direction === "up") return `Media subiendo: antes ${trend.previous}, ahora ${trend.current}`;
  if (trend.direction === "down") return `Media bajando: antes ${trend.previous}, ahora ${trend.current}`;
  return `Media estable: ${trend.current}`;
}

function renderRatingTrendChip(player: Player) {
  const trend = playerRatingTrend(player);
  if (!trend) return null;

  const icon = trend.direction === "up" ? "↑" : trend.direction === "down" ? "↓" : "→";

  return (
    <span className={`rating-trend-chip rating-trend-${trend.direction}`} title={ratingTrendText(trend)} aria-label={ratingTrendText(trend)}>
      <b aria-hidden="true">{icon}</b>
      {trend.direction === "flat" ? <em>igual</em> : <s>{trend.previous}</s>}
    </span>
  );
}

function ratingWindow(player: Player, voterId: string) {
  const ownVote = ratingHistory(player).filter((vote) => vote.voterId === voterId).at(-1);
  const isInitialWindow = !ownVote && player.appearances === 0;
  const nextMatchCount = ownVote ? ownVote.matchCount + ratingReviewInterval : isInitialWindow ? 0 : ratingReviewInterval;
  const waitMatches = Math.max(0, nextMatchCount - player.appearances);
  return {
    canRate: !player.inactive && player.appearances >= nextMatchCount,
    isInitialWindow,
    nextMatchCount,
    ownVote,
    waitMatches,
  };
}

function makeFacetRatings(base = 5) {
  return ratingFacets.reduce((next, facet) => {
    next[facet.key] = clampRating(base);
    return next;
  }, {} as Record<RatingFacet, number>);
}

type FaceDetectorLike = new (options?: { fastMode?: boolean; maxDetectedFaces?: number }) => {
  detect: (source: HTMLImageElement) => Promise<
    Array<{
      boundingBox: { x: number; y: number; width: number; height: number };
      landmarks?: Array<{ type?: string; locations?: Array<{ x: number; y: number }> }>;
    }>
  >;
};

type AvatarFace = {
  box: { x: number; y: number; width: number; height: number };
  eyes?: { x: number; y: number };
};

function readFileDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("No se pudo leer la imagen"));
    reader.onload = () => resolve(String(reader.result ?? ""));
    reader.readAsDataURL(file);
  });
}

function loadAvatarImage(source: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onerror = () => reject(new Error("No se pudo preparar la imagen"));
    image.onload = () => resolve(image);
    image.src = source;
  });
}

async function detectAvatarFace(image: HTMLImageElement) {
  const FaceDetector = (window as unknown as { FaceDetector?: FaceDetectorLike }).FaceDetector;
  if (!FaceDetector) return null;

  const faces = await withTimeout(new FaceDetector({ fastMode: true, maxDetectedFaces: 1 }).detect(image), 1200, "Detección de cara agotada");
  const face = faces
    .map((face) => face.boundingBox)
    .sort((a, b) => b.width * b.height - a.width * a.height)[0];
  const original = faces.find((item) => item.boundingBox === face) ?? faces[0];
  const eyePoints = (original?.landmarks ?? [])
    .filter((landmark) => landmark.type?.toLocaleLowerCase("es-ES").includes("eye"))
    .flatMap((landmark) => landmark.locations ?? []);

  if (!face) return null;
  return {
    box: face,
    eyes: eyePoints.length > 0
      ? {
          x: eyePoints.reduce((sum, point) => sum + point.x, 0) / eyePoints.length,
          y: eyePoints.reduce((sum, point) => sum + point.y, 0) / eyePoints.length,
        }
      : undefined,
  } satisfies AvatarFace;
}

function avatarCropArea(image: HTMLImageElement, face: AvatarFace | null) {
  const targetAspect = 560 / 720;
  const imageWidth = image.naturalWidth || image.width;
  const imageHeight = image.naturalHeight || image.height;
  const fallbackHeight = Math.min(imageHeight, imageWidth / targetAspect);
  let cropHeight = fallbackHeight;
  let centerX = imageWidth / 2;
  let anchorY = imageHeight * 0.38;

  if (face) {
    centerX = face.eyes?.x ?? face.box.x + face.box.width / 2;
    anchorY = face.eyes?.y ?? face.box.y + face.box.height * 0.42;
    cropHeight = Math.max(face.box.height * 2.8, imageHeight * 0.42);
  }

  let cropWidth = cropHeight * targetAspect;
  if (cropWidth > imageWidth) {
    cropWidth = imageWidth;
    cropHeight = cropWidth / targetAspect;
  }
  if (cropHeight > imageHeight) {
    cropHeight = imageHeight;
    cropWidth = cropHeight * targetAspect;
  }

  const x = Math.min(Math.max(centerX - cropWidth / 2, 0), Math.max(0, imageWidth - cropWidth));
  const eyeTarget = face?.eyes ? 0.31 : 0.34;
  const y = Math.min(Math.max(anchorY - cropHeight * eyeTarget, 0), Math.max(0, imageHeight - cropHeight));
  return { x, y, width: cropWidth, height: cropHeight };
}

async function avatarDataUrl(file: File) {
  if (!file.type.startsWith("image/")) throw new Error("El archivo no es una imagen");

  const source = await readFileDataUrl(file);
  const image = await loadAvatarImage(source);
  const face = await detectAvatarFace(image).catch(() => null);
  const crop = avatarCropArea(image, face);
  const keepTransparency = file.type === "image/png" || file.type === "image/webp";
  const canvas = document.createElement("canvas");
  canvas.width = 420;
  canvas.height = 540;
  const context = canvas.getContext("2d");
  if (!context) return source;

  if (!keepTransparency) {
    context.fillStyle = "#f4df9a";
    context.fillRect(0, 0, canvas.width, canvas.height);
  }
  context.drawImage(image, crop.x, crop.y, crop.width, crop.height, 0, 0, canvas.width, canvas.height);
  if (!keepTransparency) return canvas.toDataURL("image/jpeg", 0.86);

  const webpAvatar = canvas.toDataURL("image/webp", 0.86);
  return webpAvatar.startsWith("data:image/webp") ? webpAvatar : canvas.toDataURL("image/png");
}

async function matchPhotoDataUrl(file: File) {
  if (!file.type.startsWith("image/")) throw new Error("El archivo no es una imagen");

  const source = await readFileDataUrl(file);
  const image = await loadAvatarImage(source);
  const imageWidth = image.naturalWidth || image.width;
  const imageHeight = image.naturalHeight || image.height;
  const ratio = Math.min(960 / imageWidth, 720 / imageHeight, 1);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(imageWidth * ratio));
  canvas.height = Math.max(1, Math.round(imageHeight * ratio));
  const context = canvas.getContext("2d");
  if (!context) return source;

  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL("image/jpeg", 0.78);
}

function positionMeta(position: PlayerPosition) {
  const option = Object.values(positionOptionsByKind).flat().find((item) => item.value === position);
  if (option) return { line: option.line, label: option.value, short: option.short };
  if (position === "Porteria" || position === "Defensa" || position === "Medio" || position === "Ataque") return legacyPositionMeta[position];
  return { line: "Medio" as PositionLine, label: position, short: "MED" };
}

function isGoalkeeperPosition(position: PlayerPosition | undefined) {
  return position ? positionMeta(position).line === "Porteria" : false;
}

function rememberedOutfieldPosition(player: Player, kind: MatchKind) {
  if (player.outfieldPosition && !isGoalkeeperPosition(player.outfieldPosition)) return player.outfieldPosition;
  if (!isGoalkeeperPosition(player.position)) return player.position;
  return defaultPositionForKind(kind);
}

function playerPosition(player: Player): PositionLine {
  return player.goalkeeperOnly ? "Porteria" : positionMeta(player.position).line;
}

function positionRank(player: Player) {
  const order: Record<PositionLine, number> = { Porteria: 0, Defensa: 1, Medio: 2, Ataque: 3 };
  return order[playerPosition(player)];
}

function sortedLineupPlayers(players: Player[], scoreForPlayer: PlayerScoreFn = scorePlayer) {
  return [...players].sort((a, b) => positionRank(a) - positionRank(b) || scoreForPlayer(b) - scoreForPlayer(a) || a.name.localeCompare(b.name, "es"));
}

function positionLabel(player: Player) {
  return player.goalkeeperOnly ? "Portero" : positionMeta(player.position).label;
}

function positionShort(player: Player) {
  return player.goalkeeperOnly ? "POR" : positionMeta(player.position).short;
}

function ratingFacetsForPlayer(player: Player) {
  return playerPosition(player) === "Porteria" ? goalkeeperRatingFacets : fieldRatingFacets;
}

function ratingRoleForPlayer(player: Player): RatingRole {
  return playerPosition(player) === "Porteria" ? "goalkeeper" : "field";
}

function ratingVotesForRole(player: Player, role = ratingRoleForPlayer(player)) {
  const votes = player.ratingVotes ?? [];
  const roleVotes = votes.filter((vote) => vote.ratingRole === role);
  if (roleVotes.length > 0) return roleVotes;
  return votes.filter((vote) => !vote.ratingRole);
}

function defaultPositionForKind(kind: MatchKind): PlayerPosition {
  if (kind === "sala") return "Ala derecha";
  if (kind === "futbol11") return "Interior / volante";
  return "Mediocentro / pivote";
}

function equivalentPositionForKind(position: PlayerPosition, kind: MatchKind): PlayerPosition {
  if (positionOptionsByKind[kind].some((option) => option.value === position)) return position;
  const line = positionMeta(position).line;

  if (kind === "sala") {
    if (line === "Porteria") return "Portero";
    if (line === "Defensa") return "Cierre";
    if (line === "Ataque") return "Pívot";
    return "Ala derecha";
  }

  if (kind === "futbol11") {
    if (line === "Porteria") return "Portero";
    if (line === "Defensa") return "Defensa central";
    if (line === "Ataque") return "Delantero centro";
    return "Interior / volante";
  }

  if (line === "Porteria") return "Portero";
  if (line === "Defensa") return "Defensa central";
  if (line === "Ataque") return "Delantero / punta";
  return "Mediocentro / pivote";
}

function playerGames(player: Player) {
  return Math.max(0, Math.floor(player.appearances || 0));
}

function playerGoalsPerMatch(player: Player) {
  const games = playerGames(player);
  return games > 0 ? player.goals / games : 0;
}

function playerWinRate(player: Player) {
  const games = playerGames(player);
  return games > 0 ? player.wins / games : 0.5;
}

function playerRoleBalanceBonus(player: Player) {
  const line = playerPosition(player);
  if (player.goalkeeperOnly) return 0.45;
  if (line === "Porteria") return 0.3;
  if (line === "Defensa") return 0.16;
  if (line === "Ataque") return 0.12;
  return 0.08;
}

function playerBalancePower(player: Player, scoreForPlayer: PlayerScoreFn = scorePlayer) {
  const ratingPower = scoreForPlayer(player);
  const scorerPower = Math.min(1.15, playerGoalsPerMatch(player) * 0.9);
  const winPower = (playerWinRate(player) - 0.5) * 0.7;
  const experiencePower = Math.min(0.38, Math.log1p(playerGames(player)) / 7);
  return ratingPower + scorerPower + winPower + experiencePower + playerRoleBalanceBonus(player);
}

function teamBalanceMetrics(players: Player[], scoreForPlayer: PlayerScoreFn = scorePlayer): TeamBalanceMetrics {
  if (players.length === 0) {
    return {
      averageRating: 0,
      goalsPerMatch: 0,
      keeperCount: 0,
      power: 0,
      winRate: 0,
    };
  }

  return {
    averageRating: players.reduce((sum, player) => sum + scoreForPlayer(player), 0) / players.length,
    goalsPerMatch: players.reduce((sum, player) => sum + playerGoalsPerMatch(player), 0),
    keeperCount: players.filter((player) => playerPosition(player) === "Porteria").length,
    power: players.reduce((sum, player) => sum + playerBalancePower(player, scoreForPlayer), 0),
    winRate: players.reduce((sum, player) => sum + playerWinRate(player), 0) / players.length,
  };
}

function teamBalanceSummary(teamA: Player[], teamB: Player[], scoreForPlayer: PlayerScoreFn = scorePlayer) {
  const metricsA = teamBalanceMetrics(teamA, scoreForPlayer);
  const metricsB = teamBalanceMetrics(teamB, scoreForPlayer);
  const hasPlayers = teamA.length > 0 || teamB.length > 0;
  const rawDiff = metricsA.power - metricsB.power;
  const diff = Math.abs(rawDiff);
  const baseline = Math.max(metricsA.power, metricsB.power, 1);
  const percent = hasPlayers ? Math.max(0, Math.min(100, Math.round(100 - (diff / baseline) * 100))) : 0;
  const leadingTeam = !hasPlayers || percent >= 96 ? null : rawDiff > 0 ? "Equipo 1" : "Equipo 2";
  const weakerTeam = !leadingTeam ? null : leadingTeam === "Equipo 1" ? "Equipo 2" : "Equipo 1";
  const compactEdge = leadingTeam ? `${leadingTeam.replace("Equipo ", "E")} +${ratingPoints(diff)}` : "";
  const edgeLabel = leadingTeam ? `${leadingTeam} más fuerte · ${weakerTeam} por debajo` : hasPlayers ? "Sin ventaja clara" : "Pendiente";
  const label = !hasPlayers
    ? "Pendiente"
    : percent >= 96
      ? "Muy igualado"
      : percent >= 90
        ? "Bastante igualado"
        : percent >= 82
          ? "Algo desnivelado"
          : "Desnivelado";

  return {
    compactEdge,
    detail: hasPlayers
      ? `${edgeLabel} · Diferencia ${ratingPoints(diff)} pts · usa media real, forma actual, goles/partido, victorias, experiencia, posición y porteros`
      : "Marca jugadores como Voy para calcularlo",
    edgeLabel,
    label,
    leadingTeam,
    metricsA,
    metricsB,
    percent,
    weakerTeam,
  };
}

function balanceTeams(players: Player[], scoreForPlayer: PlayerScoreFn = scorePlayer) {
  const ordered = [...players].sort((a, b) => playerBalancePower(b, scoreForPlayer) - playerBalancePower(a, scoreForPlayer));
  const teamA: Player[] = [];
  const teamB: Player[] = [];

  ordered.forEach((player) => {
    const totalA = teamA.reduce((sum, item) => sum + playerBalancePower(item, scoreForPlayer), 0);
    const totalB = teamB.reduce((sum, item) => sum + playerBalancePower(item, scoreForPlayer), 0);
    const needsKeeperA = !teamA.some((item) => playerPosition(item) === "Porteria");
    const needsKeeperB = !teamB.some((item) => playerPosition(item) === "Porteria");

    if (playerPosition(player) === "Porteria" && needsKeeperA !== needsKeeperB) {
      (needsKeeperA ? teamA : teamB).push(player);
      return;
    }

    if (teamA.length < teamB.length || (teamA.length === teamB.length && totalA <= totalB)) {
      teamA.push(player);
    } else {
      teamB.push(player);
    }
  });

  return separateGoalkeepers({ teamA, teamB });
}

function randomTeams(players: Player[]) {
  const shuffled = [...players]
    .map((player) => ({ player, order: Math.random() }))
    .sort((a, b) => a.order - b.order)
    .map((item) => item.player);

  return separateGoalkeepers({
    teamA: shuffled.filter((_, index) => index % 2 === 0),
    teamB: shuffled.filter((_, index) => index % 2 === 1),
  });
}

function separateGoalkeepers(teams: { teamA: Player[]; teamB: Player[] }) {
  const keepersA = teams.teamA.filter((player) => playerPosition(player) === "Porteria");
  const keepersB = teams.teamB.filter((player) => playerPosition(player) === "Porteria");

  if ((keepersA.length === 0 && keepersB.length === 0) || (keepersA.length > 0 && keepersB.length > 0)) return teams;

  const sourceKey = keepersA.length > 0 ? "teamA" : "teamB";
  const targetKey = sourceKey === "teamA" ? "teamB" : "teamA";
  const sourceTeam = teams[sourceKey];
  const targetTeam = teams[targetKey];
  const keeperToMove = sourceTeam.find((player) => playerPosition(player) === "Porteria");
  const fieldPlayerToSwap = targetTeam.find((player) => playerPosition(player) !== "Porteria");

  if (!keeperToMove) return teams;

  const nextSource = sourceTeam.filter((player) => player.id !== keeperToMove.id);
  const nextTarget = targetTeam.filter((player) => player.id !== fieldPlayerToSwap?.id);

  if (fieldPlayerToSwap) nextSource.push(fieldPlayerToSwap);
  nextTarget.push(keeperToMove);

  return sourceKey === "teamA"
    ? { teamA: nextSource, teamB: nextTarget }
    : { teamA: nextTarget, teamB: nextSource };
}

function savedTeams(match: Match, players: Player[], confirmedIds: string[]) {
  if (!match.teamA?.length || !match.teamB?.length) return undefined;

  const teamA = match.teamA
    .filter((playerId) => confirmedIds.includes(playerId))
    .map((playerId) => players.find((player) => player.id === playerId))
    .filter((player): player is Player => Boolean(player));
  const teamB = match.teamB
    .filter((playerId) => confirmedIds.includes(playerId))
    .map((playerId) => players.find((player) => player.id === playerId))
    .filter((player): player is Player => Boolean(player));
  const assigned = new Set([...teamA, ...teamB].map((player) => player.id));
  const unassigned = players.filter((player) => confirmedIds.includes(player.id) && !assigned.has(player.id));

  unassigned.forEach((player) => {
    if (teamA.length <= teamB.length) {
      teamA.push(player);
    } else {
      teamB.push(player);
    }
  });

  return separateGoalkeepers({ teamA, teamB });
}

function automaticPitchPlayerOrder(players: Player[], scoreForPlayer: PlayerScoreFn = scorePlayer) {
  return [...players].sort((a, b) => {
    const order: Record<PositionLine, number> = { Porteria: 0, Defensa: 1, Medio: 2, Ataque: 3 };
    return order[playerPosition(a)] - order[playerPosition(b)] || scoreForPlayer(b) - scoreForPlayer(a);
  });
}

function pitchOrderedPlayers(players: Player[], slotIds?: LineupSlotPlayerId[], scoreForPlayer: PlayerScoreFn = scorePlayer) {
  if (!slotIds?.length) return automaticPitchPlayerOrder(players, scoreForPlayer);

  const playersById = new Map(players.map((player) => [player.id, player]));
  const used = new Set<string>();
  const ordered: Player[] = [];

  slotIds.forEach((playerId) => {
    if (!playerId) return;
    if (used.has(playerId)) return;
    const player = playersById.get(playerId);
    if (!player) return;
    used.add(playerId);
    ordered.push(player);
  });

  const remaining = players.filter((player) => !used.has(player.id));
  return [...ordered, ...automaticPitchPlayerOrder(remaining, scoreForPlayer)];
}

function pitchOrderedPlayerIds(players: Player[], slotIds?: LineupSlotPlayerId[], scoreForPlayer: PlayerScoreFn = scorePlayer) {
  return pitchOrderedPlayers(players, slotIds, scoreForPlayer).map((player) => player.id);
}

function compactLineupSlotIds(slotIds: LineupSlotPlayerId[]) {
  return slotIds.filter((playerId): playerId is string => Boolean(playerId));
}

function trimLineupSlots(slotIds: LineupSlotPlayerId[]) {
  const trimmed = [...slotIds];
  while (trimmed.length > 0 && !trimmed.at(-1)) trimmed.pop();
  return trimmed;
}

function automaticPitchSlotPlayerIds(players: Player[], kind: MatchKind, side: "bottom" | "left" | "right" | "top", scoreForPlayer: PlayerScoreFn = scorePlayer) {
  const slots = formationSlots(kind, side).map((slot) => ({ ...slot }));
  const slotIds: LineupSlotPlayerId[] = Array.from({ length: slots.length }, () => null);
  const extras: string[] = [];

  automaticPitchPlayerOrder(players, scoreForPlayer).forEach((player) => {
    const preferredIndex = slots.findIndex((slot) => !slot.used && slot.position === playerPosition(player));
    const fallbackIndex = slots.findIndex((slot) => !slot.used);
    const slotIndex = preferredIndex >= 0 ? preferredIndex : fallbackIndex;
    if (slotIndex < 0) {
      extras.push(player.id);
      return;
    }

    slots[slotIndex].used = true;
    slotIds[slotIndex] = player.id;
  });

  return [...slotIds, ...extras];
}

function pitchSlotPlayerIds(players: Player[], slotIds: LineupSlotPlayerId[] | undefined, scoreForPlayer: PlayerScoreFn = scorePlayer, slotCount = players.length) {
  const automaticIds = automaticPitchPlayerOrder(players, scoreForPlayer).map((player) => player.id);
  if (!slotIds?.length) return automaticIds;

  const playerIds = new Set(players.map((player) => player.id));
  const used = new Set<string>();
  const slots: LineupSlotPlayerId[] = Array.from({ length: Math.max(slotCount, Math.min(slotIds.length, slotCount)) }, (_, index) => {
    const playerId = slotIds[index];
    if (!playerId || used.has(playerId) || !playerIds.has(playerId)) return null;
    used.add(playerId);
    return playerId;
  });
  let remaining = automaticIds.filter((playerId) => !used.has(playerId));

  for (let index = 0; index < slots.length && remaining.length > 0; index += 1) {
    if (slots[index]) continue;
    slots[index] = remaining.shift() ?? null;
  }

  return [...slots, ...remaining];
}

function cleanLineupSlots(slots: LineupSlots | undefined, teamAIds: string[], teamBIds: string[]): LineupSlots | undefined {
  const cleanTeam = (ids: LineupSlotPlayerId[] | undefined, allowedIds: string[]) => {
    if (!ids?.length) return undefined;
    const allowed = new Set(allowedIds);
    const seen = new Set<string>();
    const cleaned = ids.map((playerId) => {
      if (!playerId || !allowed.has(playerId) || seen.has(playerId)) return null;
      seen.add(playerId);
      return playerId;
    });
    return cleaned.some(Boolean) ? trimLineupSlots(cleaned) : undefined;
  };
  const teamA = cleanTeam(slots?.teamA, teamAIds);
  const teamB = cleanTeam(slots?.teamB, teamBIds);

  return teamA?.length || teamB?.length ? { teamA, teamB } : undefined;
}

function reserveCapacity(match: Match) {
  return match.reservesAttend ? Math.max(0, Math.floor(match.reserveLimit ?? 0)) : 0;
}

function orderedGoingPlayers(match: Match) {
  return match.players
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => entry.status === "voy")
    .sort((a, b) => {
      const timeA = a.entry.joinedAt ? Date.parse(a.entry.joinedAt) || 0 : a.index;
      const timeB = b.entry.joinedAt ? Date.parse(b.entry.joinedAt) || 0 : b.index;
      return timeA - timeB || a.index - b.index;
    });
}

function matchPlayingIds(match: Match) {
  return orderedGoingPlayers(match)
    .slice(0, match.targetPlayers)
    .map(({ entry }) => entry.playerId);
}

function matchPayingIds(match: Match) {
  return orderedGoingPlayers(match)
    .slice(0, match.targetPlayers + reserveCapacity(match))
    .map(({ entry }) => entry.playerId);
}

function matchAttendingIds(match: Match) {
  const ids = new Set(matchPayingIds(match));
  match.teamA?.forEach((playerId) => ids.add(playerId));
  match.teamB?.forEach((playerId) => ids.add(playerId));
  match.scorers?.forEach((entry) => ids.add(entry.playerId));
  return ids;
}

function historicalRatingVotes(player: Player, cutoffMs: number) {
  if (!Number.isFinite(cutoffMs)) return player.ratingVotes ?? [];
  return (player.ratingVotes ?? []).filter((vote) => {
    const voteTime = Date.parse(vote.createdAt);
    return !Number.isFinite(voteTime) || voteTime <= cutoffMs;
  });
}

function playerStatsUntilMatch(player: Player, activeMatch: Match, matches: Match[]) {
  const activeTime = Date.parse(activeMatch.date);
  let appearances = 0;
  let goals = 0;
  let wins = 0;

  matches.forEach((match) => {
    if (match.scoreA === undefined || match.scoreB === undefined) return;
    const matchTime = Date.parse(match.date);
    if (Number.isFinite(activeTime) && Number.isFinite(matchTime) && matchTime > activeTime) return;
    if (!matchAttendingIds(match).has(player.id)) return;

    appearances += 1;
    goals += matchGoalsForPlayer(match, player.id);

    const side = teamSideForPlayer(match, player.id);
    if (side && teamScoreForSide(match, side) > teamScoreForSide(match, side === "A" ? "B" : "A")) {
      wins += 1;
    }
  });

  return { appearances, goals, wins };
}

function historicalPlayerSnapshot(player: Player, activeMatch: Match, matches: Match[]) {
  const cutoffMs = Date.parse(activeMatch.date);
  const stats = playerStatsUntilMatch(player, activeMatch, matches);

  return {
    ...player,
    appearances: stats.appearances,
    goals: stats.goals,
    ratingVotes: historicalRatingVotes(player, cutoffMs),
    wins: stats.wins,
  };
}

function historicalPlayerFormState(player: Player): PlayerFormState {
  return {
    balanceScore: scorePlayer(player),
    hasData: false,
    label: null,
    notes: ["snapshot histórico"],
    percent: 100,
    recentAverage: null,
    reliability: playerReliability(player),
    status: "normal",
  };
}

function playerLastActivityInGroup(player: Player, matches: Match[]) {
  const matchActivity = matches
    .filter((match) => matchHasPlayerRecord(match, player.id))
    .map((match) => Date.parse(match.date) || 0);
  const voteActivity = (player.ratingVotes ?? []).map((vote) => Date.parse(vote.createdAt) || 0);
  return Math.max(0, ...matchActivity, ...voteActivity);
}

function importCandidatesForUser(teams: RemoteTeam[], currentGroupId: string | null, currentUserId: string | null): PlayerImportCandidate[] {
  if (!currentUserId) return [];

  return teams
    .filter((team) => team.id !== currentGroupId)
    .flatMap((team) =>
      team.payload.players
        .filter((player) => player.ownerUserId === currentUserId)
        .map((player) => ({
          appearances: Math.max(0, Number(player.appearances) || 0),
          groupId: team.id,
          groupName: team.name,
          inactive: Boolean(player.inactive),
          key: `${team.id}:${player.id}`,
          lastActivity: playerLastActivityInGroup(player, team.payload.matches),
          media: peerAverage(player),
          player,
        })),
    )
    .sort((a, b) =>
      Number(a.inactive) - Number(b.inactive) ||
      b.media - a.media ||
      b.appearances - a.appearances ||
      b.lastActivity - a.lastActivity ||
      playerDisplayName(a.player).localeCompare(playerDisplayName(b.player), "es"),
    );
}

function matchHasPlayerRecord(match: Match, playerId: string) {
  return Boolean(
    match.players.some((entry) => entry.playerId === playerId) ||
      match.teamA?.includes(playerId) ||
      match.teamB?.includes(playerId) ||
      match.scorers?.some((entry) => entry.playerId === playerId),
  );
}

function consecutiveAbsenceStreak(matches: Match[], playerId: string) {
  const finalizedMatches = matches
    .filter((match) => match.scoreA !== undefined)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
  const firstKnownMatch = finalizedMatches.find((match) => matchHasPlayerRecord(match, playerId));

  if (!firstKnownMatch) return 0;

  let streak = 0;
  const firstKnownTime = new Date(firstKnownMatch.date).getTime();

  for (const match of [...finalizedMatches].reverse()) {
    if (new Date(match.date).getTime() < firstKnownTime) break;
    if (matchAttendingIds(match).has(playerId)) break;
    streak += 1;
  }

  return streak;
}

function nextPayer(players: Player[], matches: Match[], activeMatch: Match, confirmedIds: string[]) {
  if (confirmedIds.length === 0) return undefined;

  const orderedIds = players.map((player) => player.id);
  const pickAfter = (lastPayerId: string | undefined, candidateIds: string[]) => {
    const previousIndex = lastPayerId ? orderedIds.indexOf(lastPayerId) : -1;
    const startIndex = previousIndex >= 0 ? previousIndex + 1 : 0;

    for (let offset = 0; offset < orderedIds.length; offset += 1) {
      const candidateId = orderedIds[(startIndex + offset) % orderedIds.length];
      if (candidateIds.includes(candidateId)) return candidateId;
    }

    return candidateIds[0];
  };

  const orderedMatches = matches
    .map((match, index) => ({ index, match }))
    .sort((a, b) => {
      const dateDiff = new Date(a.match.date).getTime() - new Date(b.match.date).getTime();
      return dateDiff === 0 ? a.index - b.index : dateDiff;
    });

  let lastPayerId: string | undefined;

  for (const { match } of orderedMatches) {
    if (match.id === activeMatch.id) break;
    const matchConfirmedIds = matchPayingIds(match);
    if (matchConfirmedIds.length === 0) continue;
    lastPayerId = match.payerId && matchConfirmedIds.includes(match.payerId) ? match.payerId : pickAfter(lastPayerId, matchConfirmedIds);
  }

  return pickAfter(lastPayerId, confirmedIds);
}

type PitchBoardColor = "team-a" | "team-b";

type PitchBoardPoint = {
  x: number;
  y: number;
};

type PitchBoardLine = {
  color: PitchBoardColor;
  id: string;
  points: PitchBoardPoint[];
};

type PitchBoardState = {
  active: boolean;
  color: PitchBoardColor;
  lines: PitchBoardLine[];
  playerPositions: Record<string, PitchBoardPoint>;
  playersVisible: boolean;
};

type FullscreenCapableDocument = Document & {
  webkitExitFullscreen?: () => Promise<void> | void;
  webkitFullscreenElement?: Element | null;
};

type FullscreenCapableElement = HTMLElement & {
  webkitRequestFullscreen?: () => Promise<void> | void;
};

function initialPitchBoardState(): PitchBoardState {
  return {
    active: false,
    color: "team-a",
    lines: [],
    playerPositions: {},
    playersVisible: true,
  };
}

function isGameFullscreenActive() {
  const fullscreenDocument = document as FullscreenCapableDocument;
  return Boolean(document.fullscreenElement ?? fullscreenDocument.webkitFullscreenElement);
}

function canRequestGameFullscreen() {
  const fullscreenElement = document.documentElement as FullscreenCapableElement;
  const hasFullscreenApi = Boolean(fullscreenElement.requestFullscreen ?? fullscreenElement.webkitRequestFullscreen);
  const hasTouchInput = window.matchMedia("(pointer: coarse)").matches || navigator.maxTouchPoints > 0;
  const isLandscape = window.matchMedia("(orientation: landscape)").matches;

  return hasFullscreenApi && hasTouchInput && isLandscape;
}

async function requestGameFullscreen() {
  if (!canRequestGameFullscreen() || isGameFullscreenActive()) return false;

  const fullscreenElement = document.documentElement as FullscreenCapableElement;

  try {
    if (fullscreenElement.requestFullscreen) {
      await fullscreenElement.requestFullscreen({ navigationUI: "hide" });
      return true;
    }

    await fullscreenElement.webkitRequestFullscreen?.();
    return true;
  } catch {
    return false;
  }
}

async function exitGameFullscreen() {
  const fullscreenDocument = document as FullscreenCapableDocument;
  if (!isGameFullscreenActive()) return;

  try {
    if (document.exitFullscreen) {
      await document.exitFullscreen();
      return;
    }

    await fullscreenDocument.webkitExitFullscreen?.();
  } catch {
    // Exiting fullscreen is best-effort; the user can always leave it with system controls.
  }
}

export default function Home({ entryRoute }: { entryRoute?: HomeEntryRoute } = {}) {
  function currentEntrySearch() {
    if (!entryRoute) return typeof window === "undefined" ? "" : window.location.search;

    const params = new URLSearchParams();
    if (entryRoute.teamCode) params.set("equipo", entryRoute.teamCode);
    if (entryRoute.matchId) params.set("p", entryRoute.matchId);
    if (entryRoute.inviteToken) params.set("i", entryRoute.inviteToken);
    if (entryRoute.adminInviteToken) params.set("a", entryRoute.adminInviteToken);
    return `?${params.toString()}`;
  }
  const [players, setPlayers] = useState<Player[]>(seedPlayers);
  const [venues, setVenues] = useState<Venue[]>(seedVenues);
  const [matches, setMatches] = useState<Match[]>(seedMatches);
  const [activeMatchId, setActiveMatchId] = useState(seedMatches[0].id);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [newVenue, setNewVenue] = useState({ address: "", cost: "56", kind: "futbol7" as MatchKind, name: "" });
  const [ratingComparisons, setRatingComparisons] = useState<Record<AttributeKey, RatingComparison>>(() => (
    Object.fromEntries(ATTRIBUTE_KEYS.map((facet) => [facet, "PARECIDO"])) as Record<AttributeKey, RatingComparison>
  ));
  const [ratingEligibility, setRatingEligibility] = useState<RatingEligibility | null>(null);
  const [ratingEligibilityLoading, setRatingEligibilityLoading] = useState(false);
  const [ratingEligibilityRevision, setRatingEligibilityRevision] = useState(0);
  const [selectedVenuePlace, setSelectedVenuePlace] = useState<VenuePlace | null>(null);
  const [venuePlaceMessage, setVenuePlaceMessage] = useState("");
  const [venuePlaceStatus, setVenuePlaceStatus] = useState<"error" | "idle" | "loading" | "missing-key" | "ready">("idle");
  const [marketZoneDraft, setMarketZoneDraft] = useState("");
  const [marketZoneRadiusKm, setMarketZoneRadiusKm] = useState(defaultMarketZoneRadiusKm);
  const [marketZonePlaceMessage, setMarketZonePlaceMessage] = useState("");
  const [marketZonePlaceStatus, setMarketZonePlaceStatus] = useState<"error" | "idle" | "loading" | "missing-key" | "ready">("idle");
  const [openQuickForm, setOpenQuickForm] = useState<"venue" | "team" | null>(null);
  const [createMenuOpen, setCreateMenuOpen] = useState(false);
  const [selectedImportCandidateKey, setSelectedImportCandidateKey] = useState<string | null>(null);
  const [showImportChoices, setShowImportChoices] = useState(false);
  const [teamGalleryOpen, setTeamGalleryOpen] = useState(false);
  const [pitchBoardState, setPitchBoardState] = useState<PitchBoardState>(() => initialPitchBoardState());
  const [pitchZoomOpen, setPitchZoomOpen] = useState(false);
  const [activeMobileTab, setActiveMobileTab] = useState<MobileAppTab>("inicio");
  const [activeMatchManagerPane, setActiveMatchManagerPane] = useState<MatchManagerPane>("proximo");
  const [editingMatchNumberField, setEditingMatchNumberField] = useState<"fieldCost" | "reserveLimit" | null>(null);
  const [matchFieldCostDraft, setMatchFieldCostDraft] = useState("");
  const [matchReserveLimitDraft, setMatchReserveLimitDraft] = useState("");
  const [profilePane, setProfilePane] = useState<ProfilePane>("ficha");
  const [playerProfileMode, setPlayerProfileMode] = useState<PlayerProfileMode>("edit");
  const [profileFocusTarget, setProfileFocusTarget] = useState<ProfileFocusTarget | null>(null);
  const [previewDemoMode, setPreviewDemoMode] = useState(false);
  const [playerActionMenu, setPlayerActionMenu] = useState<{ playerId: string; maxHeight: number; placement: "down" | "up"; x: number; y: number } | null>(null);
  const [statusConfirmation, setStatusConfirmation] = useState<PendingStatusChange | null>(null);
  const [mobileAccountOpen, setMobileAccountOpen] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [siteSettings, setSiteSettings] = useState<SiteSettings>(defaultSiteSettings);
  const [settingsDraft, setSettingsDraft] = useState<SiteSettings>(defaultSiteSettings);
  const [result, setResult] = useState({ a: "", b: "" });
  const [rankingSeason, setRankingSeason] = useState(seasonKey(new Date()));
  const [historySeason, setHistorySeason] = useState("all");
  const [rankingSort, setRankingSort] = useState<RankingSort>("media");
  const [currentDateValue, setCurrentDateValue] = useState(() => dateInputValue(new Date()));
  const [currentTimeMs, setCurrentTimeMs] = useState(() => Date.now());
  const [remoteGroupId, setRemoteGroupId] = useState<string | null>(null);
  const [remoteInviteToken, setRemoteInviteToken] = useState<string | null>(null);
  const [remotePayloadRevision, setRemotePayloadRevision] = useState<number | null>(null);
  const [remoteReady, setRemoteReady] = useState(false);
  const [syncStatus, setSyncStatus] = useState<"connecting" | "error" | "live" | "local">("local");
  const [syncError, setSyncError] = useState("");
  const [sharedMatchAccessDenied, setSharedMatchAccessDenied] = useState(false);
  const [remoteTeams, setRemoteTeams] = useState<RemoteTeam[]>([]);
  const [teamMembers, setTeamMembers] = useState<RemoteMember[]>([]);
  const [currentRole, setCurrentRole] = useState<MemberRole | null>(null);
  const { previewRequested, toggleAdminViewPreview } = useAdminViewPreview();
  const [rewardBoxDemoOpen, setRewardBoxDemoOpen] = useState(false);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [profileName, setProfileName] = useState("");
  const [newTeamName, setNewTeamName] = useState("Mi grupo de pachangas");
  const [adminInviteToken, setAdminInviteToken] = useState<string | null>(null);
  const [avatarMessage, setAvatarMessage] = useState("");
  const [avatarPromptCopied, setAvatarPromptCopied] = useState(false);
  const [avatarDrafts, setAvatarDrafts] = useState<Record<string, AvatarDraft>>({});
  const [avatarAdjustingPlayerId, setAvatarAdjustingPlayerId] = useState<string | null>(null);
  const [teamPhotoMessage, setTeamPhotoMessage] = useState("");
  const [matchPhotoPreview, setMatchPhotoPreview] = useState<{ src: string; title: string } | null>(null);
  const [profileSaveMessage, setProfileSaveMessage] = useState("");
  const [profileSaving, setProfileSaving] = useState(false);
  const [selectedPlayerCosmetics, setSelectedPlayerCosmetics] = useState<PublicPlayerCosmeticsSnapshot | null>(null);
  const [playerAssessment, setPlayerAssessment] = useState<PlayerAssessmentFlow | null>(null);
  const [playerAssessmentMessage, setPlayerAssessmentMessage] = useState("");
  const [matchWeather, setMatchWeather] = useState<MatchWeather | null>(null);
  const [matchWeatherMessage, setMatchWeatherMessage] = useState("");
  const [matchWeatherStatus, setMatchWeatherStatus] = useState<"error" | "idle" | "loading" | "ready" | "unavailable">("idle");
  const [showBillingPanel, setShowBillingPanel] = useState(false);
  const [billingLoading, setBillingLoading] = useState<false | BillingInterval | "portal">(false);
  const [billingMessage, setBillingMessage] = useState("");
  const [teamBackups, setTeamBackups] = useState<TeamBackup[]>([]);
  const [backupsLoading, setBackupsLoading] = useState(false);
  const [backupMessage, setBackupMessage] = useState("");
  const [openMatchRequests, setOpenMatchRequests] = useState<PublicMatchRequest[]>([]);
  const [openMatchRequestMessage, setOpenMatchRequestMessage] = useState("");
  const [localHydrated, setLocalHydrated] = useState(false);
  const [incomingSharedLink, setIncomingSharedLink] = useState<IncomingSharedLink>(() => (
    entryRoute
      ? incomingSharedLinkFromSearch(currentEntrySearch())
      : { hasAdminInvite: false, hasInvite: false, hasMatch: false, teamCode: null }
  ));
  const hasIncomingSharedLink = incomingSharedLink.hasInvite || incomingSharedLink.hasAdminInvite || incomingSharedLink.hasMatch || Boolean(incomingSharedLink.teamCode);
  const isDemoMode = previewDemoMode || (!hasIncomingSharedLink && !remoteReady && remoteTeams.length === 0);
  const applyingRemoteRef = useRef(false);
  const payloadRef = useRef<AppPayload | null>(null);
  const lastCommittedPayloadJsonRef = useRef("");
  const autosaveInFlightRef = useRef(false);
  const remotePayloadRevisionRef = useRef<number | null>(null);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const createMenuRef = useRef<HTMLDivElement>(null);
  const teamAccessPanelRef = useRef<HTMLElement>(null);
  const matchPanelRef = useRef<HTMLElement>(null);
  const settingsPanelRef = useRef<HTMLElement>(null);
  const billingPanelRef = useRef<HTMLElement>(null);
  const teamGalleryRef = useRef<HTMLElement>(null);
  const teamFormRef = useRef<HTMLFormElement>(null);
  const venueFormRef = useRef<HTMLFormElement>(null);
  const venueNameInputRef = useRef<HTMLInputElement>(null);
  const marketZoneInputRef = useRef<HTMLInputElement>(null);
  const playerProfileRef = useRef<HTMLDivElement>(null);
  const playerRatingFacetGridRef = useRef<HTMLDivElement>(null);
  const teamGalleryReturnScrollYRef = useRef<number | null>(null);
  const profileReturnTargetRef = useRef<ProfileReturnTarget | null>(null);
  const avatarDragRef = useRef<{ playerId: string; startX: number; startY: number; startOffsetX: number; startOffsetY: number } | null>(null);
  const rosterRailDragRef = useRef<{ dragged: boolean; pointerId: number; scrollLeft: number; startX: number; startY: number } | null>(null);
  const suppressRosterRailClickRef = useRef(false);
  const cameraVideoRef = useRef<HTMLVideoElement>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);
  const handledMobileEntryRef = useRef(false);
  const mobileNavigationLockRef = useRef<MobileAppTab | null>(null);
  const mobileNavigationUnlockTimerRef = useRef<number | null>(null);
  const pitchFullscreenRequestedRef = useRef(false);
  const [cameraPlayerId, setCameraPlayerId] = useState<string | null>(null);
  const [cameraError, setCameraError] = useState("");
  const [avatarDragging, setAvatarDragging] = useState(false);

  useEffect(() => {
    const refreshDate = () => {
      const now = new Date();
      setCurrentDateValue(dateInputValue(now));
      setCurrentTimeMs(now.getTime());
    };
    refreshDate();
    const interval = window.setInterval(refreshDate, 60 * 1000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    if (handledMobileEntryRef.current) return;
    handledMobileEntryRef.current = true;

    const requestedParams = new URLSearchParams(window.location.search);
    const requestedTab = requestedParams.get("mobile");
    const requestedMatchPane = requestedParams.get("pane");
    const managerLandscape = isMobileManagerLandscape();
    if (requestedTab === "partido") {
      lockMobileNavigationTab("partido");
      setActiveMobileTab("partido");
      if (requestedMatchPane === "admin") setActiveMatchManagerPane("admin");
      window.requestAnimationFrame(() => {
        document.getElementById("partido")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
      return;
    }

    if (requestedTab === "equipo") {
      lockMobileNavigationTab("equipo");
      setActiveMobileTab("equipo");
      setProfilePane("ranking");
      setTeamGalleryOpen(false);
      return;
    }

    if (requestedTab === "perfil") {
      lockMobileNavigationTab("perfil");
      setActiveMobileTab("perfil");
      if (managerLandscape) {
        setPlayerProfileMode("edit");
        setProfilePane("ficha");
        setSelectedPlayerId(ownPlayer?.id ?? selectedPlayerId ?? players[0]?.id ?? "");
      }
      setMobileAccountOpen(!managerLandscape);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mobile entry is intentionally handled once from the initial URL.
  }, []);

  useEffect(() => {
    if (!mobileAccountOpen) return;

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMobileAccountOpen(false);
    };

    document.addEventListener("keydown", closeOnEscape);
    document.body.classList.add("mobile-sheet-open");
    return () => {
      document.removeEventListener("keydown", closeOnEscape);
      document.body.classList.remove("mobile-sheet-open");
    };
  }, [mobileAccountOpen]);

  useEffect(() => {
    if (!matchPhotoPreview) return;

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMatchPhotoPreview(null);
    };

    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [matchPhotoPreview]);

  useEffect(() => {
    return () => {
      if (mobileNavigationUnlockTimerRef.current !== null) {
        window.clearTimeout(mobileNavigationUnlockTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!createMenuOpen) return;

    function closeCreateMenu(event: PointerEvent) {
      if (createMenuRef.current?.contains(event.target as Node)) return;
      setCreateMenuOpen(false);
    }

    function closeCreateMenuWithKeyboard(event: KeyboardEvent) {
      if (event.key === "Escape") setCreateMenuOpen(false);
    }

    document.addEventListener("pointerdown", closeCreateMenu);
    document.addEventListener("keydown", closeCreateMenuWithKeyboard);
    return () => {
      document.removeEventListener("pointerdown", closeCreateMenu);
      document.removeEventListener("keydown", closeCreateMenuWithKeyboard);
    };
  }, [createMenuOpen]);

  useEffect(() => {
    if (openQuickForm !== "venue") return;
    setVenuePlaceMessage("");
    setSelectedVenuePlace(null);

    if (!googleMapsApiKey) {
      setVenuePlaceStatus("missing-key");
      return;
    }

    const input = venueNameInputRef.current;
    if (!input) return;

    let cleanup: (() => void) | undefined;
    let disposed = false;
    setVenuePlaceStatus("loading");

    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input,
      onPlace: (place) => {
        if (disposed) return;
        setSelectedVenuePlace(place);
        setNewVenue((current) => ({ ...current, address: place.address, name: place.name }));
        setVenuePlaceMessage("");
      },
    })
      .then((nextCleanup) => {
        if (disposed) {
          nextCleanup();
          return;
        }
        cleanup = nextCleanup;
        setVenuePlaceStatus("ready");
      })
      .catch((error: unknown) => {
        if (disposed) return;
        setVenuePlaceStatus("error");
        setVenuePlaceMessage(error instanceof Error ? error.message : "No se pudo cargar Google Places.");
      });

    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [openQuickForm]);

  const openPitchZoom = useCallback(() => {
    setPitchZoomOpen(true);
    void requestGameFullscreen().then((enteredFullscreen) => {
      if (enteredFullscreen) pitchFullscreenRequestedRef.current = true;
    });
  }, []);

  const closePitchZoom = useCallback(() => {
    setPitchZoomOpen(false);
    if (!pitchFullscreenRequestedRef.current) return;

    pitchFullscreenRequestedRef.current = false;
    void exitGameFullscreen();
  }, []);

  useEffect(() => {
    if (!pitchZoomOpen) return;

    function closePitchZoomWithKeyboard(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      closePitchZoom();
    }

    document.addEventListener("keydown", closePitchZoomWithKeyboard);
    return () => document.removeEventListener("keydown", closePitchZoomWithKeyboard);
  }, [closePitchZoom, pitchZoomOpen]);

  useEffect(() => {
    const clearFullscreenRequestFlag = () => {
      if (!isGameFullscreenActive()) pitchFullscreenRequestedRef.current = false;
    };

    document.addEventListener("fullscreenchange", clearFullscreenRequestFlag);
    document.addEventListener("webkitfullscreenchange", clearFullscreenRequestFlag);
    return () => {
      document.removeEventListener("fullscreenchange", clearFullscreenRequestFlag);
      document.removeEventListener("webkitfullscreenchange", clearFullscreenRequestFlag);
    };
  }, []);

  function currentPayload(): AppPayload {
    return {
      activeMatchId,
      matches,
      players,
      siteSettings,
      venues,
    };
  }
  payloadRef.current = currentPayload();

  function setRemoteRevision(revision: number | string | null | undefined) {
    const nextRevision = revision === null || revision === undefined ? null : Number(revision);
    if (nextRevision !== null && !Number.isFinite(nextRevision)) return;
    remotePayloadRevisionRef.current = nextRevision;
    setRemotePayloadRevision(nextRevision);
  }

  function applyPayload(payload: AppPayload, revision?: number | string | null) {
    applyingRemoteRef.current = true;
    lastCommittedPayloadJsonRef.current = serializePayload(payload);
    setPlayers(payload.players);
    setVenues(payload.venues);
    setSiteSettings(payload.siteSettings);
    setMatches(payload.matches);
    setActiveMatchId(payload.activeMatchId);
    if (revision !== undefined) setRemoteRevision(revision);
    window.setTimeout(() => {
      applyingRemoteRef.current = false;
    }, 250);
  }

  function applyRemoteCommit(commit: RemotePayloadCommit | null | undefined) {
    if (!commit?.payload) return false;
    applyPayload(normalizePayload(commit.payload), commit.confirmedRevision ?? commit.payload_revision);
    applyBillingFromCommit(commit);
    if (remoteGroupId && (commit.ratingsEnabled !== undefined || commit.ratings_enabled !== undefined)) {
      const ratingsEnabled = commit.ratingsEnabled ?? commit.ratings_enabled ?? true;
      setRemoteTeams((current) => current.map((team) => (team.id === remoteGroupId ? { ...team, ratingsEnabled } : team)));
    }
    setSyncStatus("live");
    setSyncError("");
    return true;
  }

  function applyBillingFromCommit(commit: RemotePayloadCommit | null | undefined) {
    if (!commit || !remoteGroupId) return;
    if (
      commit.billing_status === undefined &&
      commit.billing_trial_finalized_matches === undefined &&
      commit.stripe_customer_id === undefined &&
      commit.stripe_subscription_id === undefined &&
      commit.stripe_price_id === undefined &&
      commit.stripe_current_period_end === undefined &&
      commit.billing_interval === undefined
    ) return;

    const patch = billingPatchFromRecord(commit as Record<string, unknown>);
    setRemoteTeams((current) => current.map((team) => (team.id === remoteGroupId ? { ...team, ...patch } : team)));
  }

  function applyBillingFromGroupRow(row: Record<string, unknown>) {
    const rowId = row.id ? String(row.id) : remoteGroupId;
    if (!rowId) return;
    const patch = billingPatchFromRecord(row);
    setRemoteTeams((current) => current.map((team) => (team.id === rowId ? { ...team, ...patch } : team)));
  }

  function remoteWriteErrorMessage(message = "Otro usuario ha actualizado antes. Espera la sincronización y prueba otra vez.") {
    const normalizedMessage = message.toLowerCase();
    if (normalizedMessage.includes("connection pool")) {
      return "Supabase está saturado. La app reintentará sincronizar en unos segundos.";
    }
    if (isRemoteRevisionConflict(normalizedMessage)) {
      return "El grupo cambió en otro dispositivo. Recargando datos...";
    }
    return message;
  }

  function isRemoteRevisionConflict(message: string) {
    const normalizedMessage = message.toLowerCase();
    return [
      "team changed before saving",
      "server revision is newer",
      "match revision is newer",
      "could not obtain lock",
      "could not serialize",
      "upstream request timeout",
    ].some((fragment) => normalizedMessage.includes(fragment));
  }

  function markRemoteWriteError(message = "Otro usuario ha actualizado antes. Espera la sincronización y prueba otra vez.") {
    setSyncStatus("error");
    setSyncError(remoteWriteErrorMessage(message));
    if (isRemoteRevisionConflict(message) && supabase && remoteGroupId) {
      void loadTeams(supabase, remoteGroupId).catch((error) => {
        setSyncError(error instanceof Error ? error.message : "No se pudo recargar el grupo");
      });
    }
  }

  useEffect(() => {
    function rollbackRejectedWrite(event: Event) {
      if (!remoteGroupId || !remoteReady) return;
      const rejection = (event as CustomEvent<{ code?: string; message?: string }>).detail;
      if (saveTimerRef.current) window.clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;

      try {
        if (lastCommittedPayloadJsonRef.current) {
          applyPayload(normalizePayload(JSON.parse(lastCommittedPayloadJsonRef.current)), remotePayloadRevisionRef.current);
        }
      } catch {
        // The authoritative reload below remains the fallback for a damaged local cache.
      }

      const message = rejection?.code === "CLIENT_UPDATE_REQUIRED"
        ? "Actualización obligatoria. El cambio no se ha guardado."
        : rejection?.code === "OFFLINE_WRITE_NOT_CONFIRMED"
          ? "Sin conexión. El cambio no se ha confirmado."
          : rejection?.message || "El servidor ha rechazado el cambio. Se ha restaurado el estado confirmado.";
      markRemoteWriteError(message);

      if (navigator.onLine && supabase) {
        void loadTeams(supabase, remoteGroupId).catch((error) => {
          setSyncError(error instanceof Error ? error.message : "No se pudo recargar el estado oficial");
        });
      }
    }

    window.addEventListener(PWA_WRITE_REJECTED_EVENT, rollbackRejectedWrite);
    return () => window.removeEventListener(PWA_WRITE_REJECTED_EVENT, rollbackRejectedWrite);
    // The handler intentionally follows the currently selected remote group and its canonical revision.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [remoteGroupId, remoteReady]);

  function isAnonymousAuthUser(user: User | null) {
    return Boolean(user && (user as User & { is_anonymous?: boolean }).is_anonymous);
  }

  function authDisplayName(user: User | null) {
    const metadata = user?.user_metadata as { full_name?: string; name?: string } | undefined;
    return metadata?.full_name || metadata?.name || user?.email || "Usuario";
  }

  function updateAuthState(user: User | null) {
    setAuthUser(user);
    setCurrentUserId(user?.id ?? null);
  }

  async function getSignedUser(client: NonNullable<typeof supabase>) {
    const sessionResult = await client.auth.getSession();
    const user = sessionResult.data.session?.user ?? null;
    updateAuthState(user);
    return user;
  }

  async function ensureRegisteredUser(client: NonNullable<typeof supabase>) {
    const user = await getSignedUser(client);
    if (!user || isAnonymousAuthUser(user)) {
      throw new Error("Entra con Google para crear grupos o ser admin.");
    }

    return user.id;
  }

  async function signInWithGoogle() {
    if (!supabase) {
      setSyncStatus("error");
      setSyncError("Supabase no está configurado.");
      return;
    }

    if (!googleClientId) {
      setSyncStatus("error");
      setSyncError("Falta NEXT_PUBLIC_GOOGLE_CLIENT_ID.");
      return;
    }

    const rawNonce = createGoogleRawNonce();
    const hashedNonce = await sha256Hex(rawNonce);
    localStorage.setItem(googleAuthNonceKey, rawNonce);
    localStorage.setItem(googleAuthReturnKey, window.location.href);

    const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    authUrl.searchParams.set("client_id", googleClientId);
    authUrl.searchParams.set("redirect_uri", `${window.location.origin}/auth/google`);
    authUrl.searchParams.set("response_type", "id_token");
    authUrl.searchParams.set("scope", "openid email profile");
    authUrl.searchParams.set("nonce", hashedNonce);
    authUrl.searchParams.set("prompt", "select_account");

    window.location.assign(authUrl.toString());
  }

  async function signOut() {
    if (!supabase) return;

    await supabase.auth.signOut();
    updateAuthState(null);
    setPreviewDemoMode(false);
    setRemoteGroupId(null);
    setRemoteInviteToken(null);
    setRemoteRevision(null);
    setRemoteReady(false);
    setRemoteTeams([]);
    setTeamMembers([]);
    setCurrentRole(null);
    setSyncStatus("local");
    setSyncError("");
  }

  async function loadTeamMembers(client: NonNullable<typeof supabase>, groupId: string) {
    const members = await client
      .from("pachanga_group_members")
      .select("user_id, role, display_name")
      .eq("group_id", groupId)
      .order("created_at", { ascending: true });

    if (members.error) throw new Error(members.error.message);

    setTeamMembers(
      (members.data ?? []).map((member, index) => ({
        displayName: displayName(String(member.display_name || `Jugador ${index + 1}`)),
        role: (member.role as MemberRole | null) ?? "player",
        userId: String(member.user_id),
      })),
    );

    const ownMember = (members.data ?? []).find((member) => String(member.user_id) === currentUserId);
    if (ownMember?.display_name) setProfileName(displayName(String(ownMember.display_name)));
  }

  function prettyTeamParams(team: RemoteTeam, extra?: Record<string, string | undefined>) {
    const params = new URLSearchParams();
    params.set("equipo", team.teamCode);
    Object.entries(extra ?? {}).forEach(([key, value]) => {
      if (value) params.set(key, value);
    });
    return params;
  }

  async function loadTeams(
    client: NonNullable<typeof supabase>,
    preferredGroupId?: string | null,
    preferredTeamCode?: string | null,
    options?: { previewOnly?: boolean; sharedMatchAccess?: boolean },
  ) {
    const session = await client.auth.getSession();
    const memberUserId = session.data.session?.user?.id;
    if (!memberUserId) {
      setRemoteTeams([]);
      setRemoteGroupId(null);
      setRemoteInviteToken(null);
      setRemoteRevision(null);
      setCurrentRole(null);
      setTeamMembers([]);
      setRemoteReady(false);
      setSyncStatus("local");
      return;
    }

    const memberships = await client
      .from("pachanga_group_members")
      .select(
        "group_id, role, pachanga_groups(id, name, owner_id, team_code, invite_token, payload, payload_revision, ratings_enabled, billing_status, billing_trial_finalized_matches, stripe_customer_id, stripe_subscription_id, stripe_price_id, stripe_current_period_end, billing_interval)",
      )
      .eq("user_id", memberUserId)
      .order("created_at", { ascending: true });

    if (memberships.error) throw new Error(memberships.error.message);

    const teams = (memberships.data ?? [])
      .map((membership) => {
        const group = Array.isArray(membership.pachanga_groups)
          ? membership.pachanga_groups[0]
          : membership.pachanga_groups;
        if (!group) return null;

        const rawRole = membership.role as MemberRole | null;
        const confirmedRole: MemberRole = rawRole === "owner"
          ? (String(group.owner_id ?? "") === memberUserId ? "owner" : "player")
          : rawRole === "admin" ? "admin" : "player";

        return {
          billingInterval: normalizeBillingInterval(group.billing_interval),
          billingStatus: normalizeBillingStatus(group.billing_status),
          billingTrialFinalizedMatches: Math.max(0, Math.floor(Number(group.billing_trial_finalized_matches) || 0)),
          id: String(group.id),
          inviteToken: String(group.invite_token),
          name: String(group.name ?? "Grupo de pachangas"),
          ownerId: group.owner_id ? String(group.owner_id) : null,
          payload: normalizePayload(group.payload as Partial<AppPayload>),
          payloadRevision: Number(group.payload_revision ?? 0),
          ratingsEnabled: group.ratings_enabled !== false,
          role: confirmedRole,
          stripeCustomerId: group.stripe_customer_id ? String(group.stripe_customer_id) : null,
          stripeCurrentPeriodEnd: group.stripe_current_period_end ? String(group.stripe_current_period_end) : null,
          stripePriceId: group.stripe_price_id ? String(group.stripe_price_id) : null,
          stripeSubscriptionId: group.stripe_subscription_id ? String(group.stripe_subscription_id) : null,
          teamCode: String(group.team_code ?? group.id).toUpperCase(),
        } satisfies RemoteTeam;
      })
      .filter((team): team is RemoteTeam => Boolean(team));

    setRemoteTeams(teams);

    const requestedTeam =
      teams.find((team) => team.id === preferredGroupId) ??
      teams.find((team) => team.teamCode === preferredTeamCode?.toUpperCase());
    if ((preferredGroupId || preferredTeamCode) && !requestedTeam) {
      setRemoteGroupId(null);
      setRemoteInviteToken(null);
      setRemoteRevision(null);
      setCurrentRole(null);
      setTeamMembers([]);
      setRemoteReady(false);
      setSharedMatchAccessDenied(Boolean(options?.sharedMatchAccess));
      setSyncStatus("error");
      setSyncError(options?.sharedMatchAccess
        ? "No puedes ver este partido porque no perteneces al grupo."
        : "No tienes acceso a este grupo.");
      return;
    }

    const selectedTeam = requestedTeam ?? teams[0];
    if (!selectedTeam) {
      setRemoteGroupId(null);
      setRemoteInviteToken(null);
      setRemoteRevision(null);
      setCurrentRole(null);
      setTeamMembers([]);
      setRemoteReady(false);
      setSyncStatus("local");
      return;
    }

    setSharedMatchAccessDenied(false);

    if (options?.previewOnly) {
      setRemoteGroupId(selectedTeam.id);
      setRemoteInviteToken(selectedTeam.inviteToken);
      setRemoteRevision(selectedTeam.payloadRevision);
      setCurrentRole(selectedTeam.role);
      setAdminInviteToken(null);
      setTeamMembers([]);
      setRemoteReady(false);
      setSyncStatus("local");
      setSyncError("");
      return;
    }

    setRemoteGroupId(selectedTeam.id);
    setRemoteInviteToken(selectedTeam.inviteToken);
    setRemoteRevision(selectedTeam.payloadRevision);
    setCurrentRole(selectedTeam.role);
    setAdminInviteToken(null);
    applyPayload(selectedTeam.payload, selectedTeam.payloadRevision);
    const currentParams = new URLSearchParams(currentEntrySearch());
    const sharedMatchId = expandCompactUuid(currentParams.get("p") ?? currentParams.get("partido"));
    if (sharedMatchId && selectedTeam.payload.matches.some((match) => match.id === sharedMatchId)) {
      setActiveMatchId(sharedMatchId);
    }
    setRemoteReady(true);
    setSyncStatus("live");
    setSyncError("");
    await loadTeamMembers(client, selectedTeam.id);

    if (entryRoute?.teamCode && entryRoute.matchId) {
      window.history.replaceState(null, "", window.location.pathname);
    } else {
      const nextParams = prettyTeamParams(selectedTeam, { p: sharedMatchId ? compactUuid(sharedMatchId) : undefined });
      window.history.replaceState(null, "", `${window.location.pathname}?${nextParams.toString()}`);
    }
  }

  async function loadTeamBackups(client = supabase, clearMessage = true) {
    if (!client || !isRegisteredUser) return;

    setBackupsLoading(true);
    if (clearMessage) setBackupMessage("");

    const result = await client
      .from("pachanga_group_backups")
      .select("id, source_group_id, group_name, team_code, reason, payload, created_at")
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(3);

    setBackupsLoading(false);

    if (result.error) {
      setBackupMessage("No se pudieron cargar las copias.");
      return;
    }

    setTeamBackups(
      (result.data ?? []).map((backup) => {
        const payload = normalizePayload(backup.payload as Partial<AppPayload>);

        return {
          createdAt: String(backup.created_at),
          groupName: String(backup.group_name ?? "Grupo de pachangas"),
          id: String(backup.id),
          matchCount: payload.matches.length,
          playerCount: payload.players.filter((player) => !player.inactive).length,
          reason: String(backup.reason ?? "manual"),
          sourceGroupId: backup.source_group_id ? String(backup.source_group_id) : null,
          teamCode: backup.team_code ? String(backup.team_code) : null,
        };
      }),
    );
  }

  async function createTeamBackup(reason: string, payload: AppPayload, showMessage = true) {
    if (!supabase || !remoteGroupId || !canManageTeam) return false;

    if (showMessage) {
      setBackupMessage("Creando copia...");
    }

    const result = await supabase.rpc("create_pachanga_group_backup", {
      backup_payload: payload,
      backup_reason: reason,
      target_group_id: remoteGroupId,
    });

    if (result.error) {
      setBackupMessage("No se pudo crear la copia de seguridad.");
      return false;
    }

    if (showMessage) {
      setBackupMessage("Copia de seguridad creada");
      window.setTimeout(() => setBackupMessage(""), 2200);
    }

    await loadTeamBackups(supabase, false);
    return true;
  }

  async function saveRemotePayload(payload: AppPayload) {
    if (!supabase || !remoteGroupId || !remoteReady || !canManageTeam) return false;
    const payloadJson = serializePayload(payload);
    if (payloadJson === lastCommittedPayloadJsonRef.current) {
      setSyncStatus("live");
      setSyncError("");
      return true;
    }

    setSyncStatus("connecting");
    setSyncError("");

    const saveResult = await supabase.rpc("save_pachanga_payload_authoritative_v2", {
      client_metadata: clientOperationMetadata(),
      expected_revision: remotePayloadRevisionRef.current,
      next_payload: payload,
      operation_id: id(),
      target_group_id: remoteGroupId,
    });
    if (saveResult.error) {
      markRemoteWriteError(saveResult.error.message);
      if (isRemoteRevisionConflict(saveResult.error.message)) {
        await loadTeams(supabase, remoteGroupId).catch((error) => {
          setSyncError(error instanceof Error ? error.message : "No se pudo recargar el grupo");
        });
      }
      return false;
    }

    applyRemoteCommit(saveResult.data as RemotePayloadCommit);
    lastCommittedPayloadJsonRef.current = payloadJson;
    setSyncStatus("live");
    setSyncError("");
    return true;
  }

  async function saveRemotePayloadWithBackup(payload: AppPayload, reason: string, showBackupMessage = false) {
    const saved = await saveRemotePayload(payload);
    if (!saved) return false;

    await createTeamBackup(reason, payload, showBackupMessage);
    setSyncStatus("live");
    setSyncError("");
    return true;
  }

  async function createManualBackup() {
    if (!canManageTeam) return;
    await saveRemotePayloadWithBackup(currentPayload(), "manual", true);
  }

  async function restoreTeamBackup(backup: TeamBackup) {
    if (!supabase || !isRegisteredUser) return;
    if (!window.confirm(`¿Restaurar la copia de ${backup.groupName}?`)) return;
    if (!window.confirm("Confirmación final: si el grupo sigue existiendo, se reemplazarán sus datos por esta copia.")) return;

    setBackupMessage("Restaurando copia...");
    setSyncStatus("connecting");
    setSyncError("");

    const result = await supabase.rpc("restore_pachanga_group_backup", {
      backup_id: backup.id,
    });

    if (result.error || !result.data) {
      setBackupMessage("No se pudo restaurar la copia.");
      setSyncStatus("error");
      setSyncError(result.error?.message ?? "No se pudo restaurar la copia");
      return;
    }

    await loadTeams(supabase, String(result.data));
    await loadTeamBackups(supabase);
    setBackupMessage("Grupo restaurado");
    setShowSettings(false);
    window.setTimeout(() => setBackupMessage(""), 2200);
  }

  useEffect(() => {
    setIncomingSharedLink(incomingSharedLinkFromSearch(currentEntrySearch()));
    setProfileName(localStorage.getItem(profileNameKey) ?? "");
    const params = new URLSearchParams(window.location.search);
    if (params.get("demo") === "1") {
      const nextParams = new URLSearchParams();
      const requestedTab = params.get("mobile");
      if (requestedTab === "inicio" || requestedTab === "partido" || requestedTab === "mercado" || requestedTab === "equipo" || requestedTab === "perfil") {
        nextParams.set("tab", requestedTab);
      }
      if (params.get("qaPlayer") === "1") nextParams.set("perspective", "player");
      window.location.replace(`/demo${nextParams.size ? `?${nextParams.toString()}` : ""}`);
      return;
    }

    const saved = localStorage.getItem(storageKey);
    if (!saved) {
      setLocalHydrated(true);
      return;
    }

    try {
      const parsed = parseLocalPayloadCache(saved);
      const payload = normalizePayload(parsed);
      setPlayers(payload.players);
      setVenues(payload.venues);
      setSiteSettings(payload.siteSettings);
      setMatches(payload.matches);
      setActiveMatchId(payload.activeMatchId);
    } catch {
      localStorage.removeItem(storageKey);
    }
    setLocalHydrated(true);
  }, []);

  useEffect(() => {
    localStorage.setItem(profileNameKey, profileName.trim());
  }, [profileName]);

  useEffect(() => {
    const registeredUser = Boolean(authUser && !isAnonymousAuthUser(authUser));
    if (!showSettings || !supabase || !registeredUser) return;
    void loadTeamBackups(supabase);
  }, [showSettings, authUser?.id, remoteGroupId]);

  useEffect(() => {
    if (!supabase) return;

    const client = supabase;
    let cancelled = false;

    void client.auth.getSession().then(({ data }) => {
      if (cancelled) return;
      updateAuthState(data.session?.user ?? null);
    });

    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((_event, session) => {
      updateAuthState(session?.user ?? null);
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!localHydrated || !supabase) return;

    const client = supabase;
    let cancelled = false;

    async function connectGroup() {
      setSyncStatus("connecting");
      setSyncError("");

      try {
        const params = new URLSearchParams(currentEntrySearch());
        const inviteToken = previewDemoMode ? null : expandCompactUuid(params.get("i") ?? params.get("invite"));
        const adminInviteToken = previewDemoMode ? null : expandCompactUuid(params.get("a") ?? params.get("admin"));
        const sharedMatchId = previewDemoMode ? null : expandCompactUuid(params.get("p") ?? params.get("partido"));
        const teamCode = previewDemoMode ? null : params.get("equipo");
        let groupId = previewDemoMode ? null : params.get("grupo");
        const initialUser = await getSignedUser(client);
        const linkNeedsLogin = Boolean(inviteToken || adminInviteToken || teamCode || groupId);

        setSharedMatchAccessDenied(false);

        if (linkNeedsLogin && (!initialUser || isAnonymousAuthUser(initialUser))) {
          if (!cancelled) {
            setRemoteGroupId(null);
            setRemoteInviteToken(null);
            setRemoteRevision(null);
            setRemoteReady(false);
            setRemoteTeams([]);
            setTeamMembers([]);
            setCurrentRole(null);
            setSyncStatus("local");
            setSyncError("");
          }
          return;
        }

        if (inviteToken && sharedMatchId) {
          throw new Error("Este enlace antiguo mezclaba una invitación de grupo con un partido. Pide al admin un nuevo enlace de partido seguro.");
        }

        if (adminInviteToken) {
          const userId = initialUser?.id ?? await ensureRegisteredUser(client);
          const user = initialUser?.id === userId ? initialUser : authUser?.id === userId ? authUser : (await getSignedUser(client));
          const adminJoinResult = await client.rpc("accept_pachanga_admin_invite_authoritative_v1", {
            admin_token: adminInviteToken,
            client_metadata: clientOperationMetadata(),
            expected_invite_revision: 1,
            member_name: profileName.trim() || authDisplayName(user) || "Admin",
            operation_id: id(),
          });
          if (adminJoinResult.error || !adminJoinResult.data) throw new Error(adminJoinResult.error?.message ?? "No se pudo aceptar la invitación de admin");
          groupId = String((adminJoinResult.data as { groupId?: string }).groupId ?? "");
          if (!groupId) throw new Error("El servidor no devolvió el grupo de la invitación de admin");
        } else if (inviteToken) {
          const joinResult = await client.rpc("join_pachanga_team", {
            member_name: profileName.trim() || authDisplayName(initialUser) || "Jugador",
            token: inviteToken,
          });
          if (joinResult.error || !joinResult.data) throw new Error(joinResult.error?.message ?? "No se pudo entrar al grupo");
          groupId = String(joinResult.data);
        } else {
          const user = initialUser;
          if (!user) {
            if (!cancelled) {
              setRemoteGroupId(null);
              setRemoteInviteToken(null);
              setRemoteRevision(null);
              setRemoteReady(false);
              setRemoteTeams([]);
              setTeamMembers([]);
              setCurrentRole(null);
              setSyncStatus("local");
            }
            return;
          }
        }

        await loadTeams(client, groupId, teamCode, {
          previewOnly: previewDemoMode,
          sharedMatchAccess: Boolean(sharedMatchId && !inviteToken && !adminInviteToken),
        });

        if (cancelled) return;
      } catch (error) {
        setSyncStatus("error");
        setSyncError(error instanceof Error ? error.message : "No se pudo cargar el grupo");
        return;
      }
    }

    void connectGroup();

    return () => {
      cancelled = true;
    };
  }, [localHydrated, previewDemoMode]);

  useEffect(() => {
    if (!supabase || !remoteGroupId || !remoteReady) return;

    const client = supabase;
    const channel = client
      .channel(`pachanga-group-${remoteGroupId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "pachanga_groups", filter: `id=eq.${remoteGroupId}` },
        () => {
          void client
            .from("pachanga_groups")
            .select(
              "id, payload, payload_revision, ratings_enabled, billing_status, billing_trial_finalized_matches, stripe_customer_id, stripe_subscription_id, stripe_price_id, stripe_current_period_end, billing_interval",
            )
            .eq("id", remoteGroupId)
            .single()
            .then(({ data, error }) => {
              if (error || !data) {
                setSyncStatus("error");
                setSyncError(error?.message ?? "No se pudo recuperar el estado confirmado");
                return;
              }
              const confirmedRevision = Number(data.payload_revision ?? 0);
              const currentRevision = remotePayloadRevisionRef.current;
              if (currentRevision !== null && confirmedRevision < currentRevision) return;
              applyPayload(normalizePayload(data.payload as Partial<AppPayload>), confirmedRevision);
              applyBillingFromGroupRow(data as Record<string, unknown>);
              setRemoteTeams((current) => current.map((team) => (
                team.id === remoteGroupId ? { ...team, ratingsEnabled: data.ratings_enabled !== false } : team
              )));
              setSyncStatus("live");
              setSyncError("");
            });
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [remoteGroupId, remoteReady]);

  const canAutosaveRemotePayload = Boolean(remoteGroupId && currentUserId && !selectedPlayerId && (currentRole === "owner" || currentRole === "admin"));

  useEffect(() => {
    if (previewDemoMode) return;

    const localPayload: AppPayload = { players, venues, matches, activeMatchId, siteSettings };
    const payloadJson = serializePayload(localPayload);
    localStorage.setItem(storageKey, serializeLocalPayloadCache(localPayload, remoteGroupId ? "server-cache" : "local-draft"));

    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = null;
    if (
      !supabase ||
      !remoteGroupId ||
      !remoteReady ||
      !canAutosaveRemotePayload ||
      applyingRemoteRef.current ||
      autosaveInFlightRef.current ||
      payloadJson === lastCommittedPayloadJsonRef.current
    ) return;

    const client = supabase;
    const targetGroupId = remoteGroupId;
    saveTimerRef.current = setTimeout(() => {
      const payload = payloadRef.current ?? currentPayload();
      const nextPayloadJson = serializePayload(payload);
      if (nextPayloadJson === lastCommittedPayloadJsonRef.current || autosaveInFlightRef.current) return;

      autosaveInFlightRef.current = true;
      void Promise.resolve(
        client.rpc("save_pachanga_payload_authoritative_v2", {
          client_metadata: clientOperationMetadata(),
          expected_revision: remotePayloadRevisionRef.current,
          next_payload: payload,
          operation_id: id(),
          target_group_id: targetGroupId,
        }),
      )
        .then((result) => {
          if (result.error) {
            markRemoteWriteError(result.error.message);
            if (isRemoteRevisionConflict(result.error.message)) {
              void loadTeams(client, targetGroupId).catch((error) => {
                setSyncError(error instanceof Error ? error.message : "No se pudo recargar el grupo");
              });
            }
            return;
          }

          applyRemoteCommit(result.data as RemotePayloadCommit);
        })
        .finally(() => {
          autosaveInFlightRef.current = false;
        });
    }, 850);
  }, [players, venues, matches, activeMatchId, siteSettings, canAutosaveRemotePayload, remoteGroupId, remoteReady, supabase, previewDemoMode]);

  useEffect(() => {
    if (!selectedPlayerId) return;
    scrollToPlayerProfile();
  }, [selectedPlayerId]);

  useEffect(() => {
    if (!cameraPlayerId) return;

    let cancelled = false;
    cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
    cameraStreamRef.current = null;

    async function startCamera() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setCameraError("Este navegador no permite usar la cámara aquí.");
        return;
      }

      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" }, audio: false });
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop());
          return;
        }
        cameraStreamRef.current = stream;
        if (cameraVideoRef.current) {
          cameraVideoRef.current.srcObject = stream;
          await cameraVideoRef.current.play().catch(() => undefined);
        }
      } catch {
        setCameraError("No se pudo abrir la cámara.");
      }
    }

    void startCamera();

    return () => {
      cancelled = true;
      cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
      cameraStreamRef.current = null;
    };
  }, [cameraPlayerId]);

  const activeMatch = matches.find((match) => match.id === activeMatchId) ?? matches[0];
  const activeKind = activeMatch.kind ?? "futbol7";
  const matchFinalized = Boolean(activeMatch.closed || activeMatch.scoreA !== undefined);
  useEffect(() => {
    setPitchBoardState(initialPitchBoardState());
  }, [activeMatchId, activeKind]);
  const activeVenue = venues.find((venue) => venue.id === activeMatch.venueId);
  const matchPlayersForDisplay = useMemo(
    () => matchFinalized ? players.map((player) => historicalPlayerSnapshot(player, activeMatch, matches)) : players,
    [activeMatch, matchFinalized, matches, players],
  );
  const matchPlayersById = useMemo(() => new Map(matchPlayersForDisplay.map((player) => [player.id, player])), [matchPlayersForDisplay]);
  const reserveLimit = reserveCapacity(activeMatch);
  const orderedGoingEntries = orderedGoingPlayers(activeMatch);
  const playingEntries = orderedGoingEntries.slice(0, activeMatch.targetPlayers);
  const reserveEntries = orderedGoingEntries.slice(activeMatch.targetPlayers, activeMatch.targetPlayers + reserveLimit);
  const waitingEntries = orderedGoingEntries.slice(activeMatch.targetPlayers + reserveLimit);
  const confirmedIds = playingEntries.map(({ entry }) => entry.playerId);
  const reserveIds = reserveEntries.map(({ entry }) => entry.playerId);
  const waitingIds = waitingEntries.map(({ entry }) => entry.playerId);
  const payingIds = [...confirmedIds, ...reserveIds];
  const confirmedPlayers = matchPlayersForDisplay.filter((player) => confirmedIds.includes(player.id));
  const reservePlayers = reserveIds.map((playerId) => matchPlayersById.get(playerId)).filter((player): player is Player => Boolean(player));
  const waitingPlayers = waitingIds.map((playerId) => matchPlayersById.get(playerId)).filter((player): player is Player => Boolean(player));
  const openMatches = [...matches]
    .filter((match) => match.configured && match.scoreA === undefined && !match.closed)
    .sort((a, b) => {
      const dateDelta = new Date(a.date).getTime() - new Date(b.date).getTime();
      if (dateDelta !== 0) return dateDelta;
      return (a.title || a.id).localeCompare(b.title || b.id, "es");
    });
  const closedMatches = matches
    .filter((match) => match.scoreA !== undefined)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  const playerForms = useMemo(() => playerFormStates(matches, players), [matches, players]);
  const playerMediaScore = (player: Player) => scorePlayer(player);
  const playerForm = (player: Player) => matchFinalized && matchPlayersById.has(player.id)
    ? historicalPlayerFormState(player)
    : playerForms.get(player.id) ?? playerFormState(player, matches, new Map(players.map((item) => [item.id, item])));
  const effectivePlayerScore = (player: Player) => playerForm(player).balanceScore;
  const absenceStreaks = useMemo(() => {
    const streaks = new Map<string, number>();
    players.forEach((player) => streaks.set(player.id, consecutiveAbsenceStreak(matches, player.id)));
    return streaks;
  }, [matches, players]);
  const doubtfulCount = activeMatch.players.filter((entry) => entry.status === "duda").length;
  const missing = Math.max(activeMatch.targetPlayers - confirmedPlayers.length, 0);
  const publicOpenSlots = Math.max(1, Math.min(missing || activeMatch.targetPlayers, Math.floor(Number(activeMatch.publicOpenSlots) || missing || 1)));
  const fieldCost = activeMatch.fieldCost ?? 0;
  const reserveLimitDraftValue = editingMatchNumberField === "reserveLimit" ? matchReserveLimitDraft : String(activeMatch.reserveLimit ?? 0);
  const fieldCostDraftValue = editingMatchNumberField === "fieldCost" ? matchFieldCostDraft : String(fieldCost);
  const lineupClosed = activeMatch.lineupClosed ?? false;
  const matchConfigured = Boolean(activeMatch.configured);
  useEffect(() => {
    if (editingMatchNumberField) return;
    setMatchReserveLimitDraft(String(activeMatch.reserveLimit ?? 0));
    setMatchFieldCostDraft(String(fieldCost));
  }, [activeMatch.id, activeMatch.reserveLimit, editingMatchNumberField, fieldCost]);
  const activeMatchTime = new Date(activeMatch.date).getTime();
  const previousPendingMatch = Number.isFinite(activeMatchTime)
    ? matches
        .filter((match) => {
          if (match.id === activeMatch.id || !match.configured || match.closed || match.scoreA !== undefined) return false;
          const matchTime = new Date(match.date).getTime();
          return Number.isFinite(matchTime) && matchTime < activeMatchTime;
        })
        .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())[0]
    : undefined;
  const previousPendingMatchTime = previousPendingMatch ? new Date(previousPendingMatch.date).getTime() : NaN;
  const registrationLockedByPreviousMatch = Boolean(
    matchConfigured &&
      !matchFinalized &&
      previousPendingMatch &&
      Number.isFinite(previousPendingMatchTime) &&
      previousPendingMatchTime > currentTimeMs,
  );
  const registrationOpen = matchConfigured && !registrationLockedByPreviousMatch;
  const showMatchRoster = matchConfigured && registrationOpen;
  const pendingOpenMatchRequests = openMatchRequests.filter((request) => request.status === "pending");
  const paymentReady = matchConfigured && (lineupClosed || matchFinalized);
  const matchContextStatus = matchFinalized ? "Finalizado" : !matchConfigured ? "Borrador" : lineupClosed ? "Alineación cerrada" : "Alineación abierta";
  const matchContextKind = matchFinalized ? "Histórico" : "Partido activo";
  const payingParticipantIds = paymentReady ? payingIds : [];
  const sharePerPlayer = payingParticipantIds.length > 0 ? fieldCost / payingParticipantIds.length : 0;
  const subscriptionContributionAmount = siteSettings.subscriptionContributionPeriod === "month"
    ? siteSettings.subscriptionContributionMonthlyAmount
    : siteSettings.subscriptionContributionYearlyAmount;
  const activeGroupPlayers = players.filter((player) => !player.inactive);
  const activeRosterCount = activeGroupPlayers.length;
  const groupLevel = teamLevelScore(activeGroupPlayers);
  const subscriptionContributionPerPlayer = siteSettings.subscriptionContributionEnabled && activeRosterCount > 0
    ? subscriptionContributionAmount / activeRosterCount
    : 0;
  const subscriptionContributionLabel = siteSettings.subscriptionContributionPeriod === "month" ? "mensual" : "anual";
  const paidCount = activeMatch.players.filter((entry) => payingParticipantIds.includes(entry.playerId) && entry.paid).length;
  const suggestedPayerId = paymentReady ? nextPayer(players, matches, activeMatch, payingParticipantIds) : undefined;
  const payerId = paymentReady && activeMatch.payerId && payingParticipantIds.includes(activeMatch.payerId) ? activeMatch.payerId : suggestedPayerId;
  const payer = players.find((player) => player.id === payerId);
  const balancedLineup = useMemo(() => balanceTeams(confirmedPlayers, effectivePlayerScore), [confirmedPlayers, playerForms]);
  const suggested = savedTeams(activeMatch, players, confirmedIds) ?? balancedLineup;
  const balanceSummary = teamBalanceSummary(suggested.teamA, suggested.teamB, effectivePlayerScore);
  const scoreAValue = result.a.trim() === "" ? undefined : Number(result.a);
  const scoreBValue = result.b.trim() === "" ? undefined : Number(result.b);
  const resultIsReady =
    Number.isInteger(scoreAValue) &&
    Number.isInteger(scoreBValue) &&
    Number(scoreAValue) >= 0 &&
    Number(scoreBValue) >= 0;

  useEffect(() => {
    setResult({
      a: activeMatch.scoreA === undefined ? "" : String(activeMatch.scoreA),
      b: activeMatch.scoreB === undefined ? "" : String(activeMatch.scoreB),
    });
  }, [activeMatch.id, activeMatch.scoreA, activeMatch.scoreB]);

  useEffect(() => {
    if (!matchConfigured) {
      setMatchWeather(null);
      setMatchWeatherStatus("idle");
      setMatchWeatherMessage("");
      return;
    }

    if (isDemoMode) {
      setMatchWeather({
        ...demoMatchWeather,
        forecastTime: activeMatch.date || demoMatchWeather.forecastTime,
      });
      setMatchWeatherStatus("ready");
      setMatchWeatherMessage("");
      return;
    }

    if (typeof activeVenue?.lat !== "number" || typeof activeVenue.lng !== "number") {
      setMatchWeather(null);
      setMatchWeatherStatus("unavailable");
      setMatchWeatherMessage("Elige un campo con ubicación para ver la previsión.");
      return;
    }

    const matchDate = new Date(activeMatch.date);
    if (Number.isNaN(matchDate.getTime())) {
      setMatchWeather(null);
      setMatchWeatherStatus("unavailable");
      setMatchWeatherMessage("Fecha del partido pendiente de confirmar.");
      return;
    }

    const applyWeatherPayload = (payload: WeatherApiPayload) => {
      if (!payload.available || !payload.forecast) {
        setMatchWeather(null);
        setMatchWeatherStatus("unavailable");
        setMatchWeatherMessage(payload.message ?? "Previsión no disponible para este partido.");
        return;
      }

      setMatchWeather(payload.forecast);
      setMatchWeatherStatus("ready");
      setMatchWeatherMessage("");
    };
    const nowMs = Date.now();
    const msUntilMatch = matchDate.getTime() - nowMs;
    if (msUntilMatch > weatherForecastClientLimitMs) {
      const msUntilAvailable = Math.max(0, msUntilMatch - weatherForecastClientLimitMs);
      const daysUntilAvailable = Math.max(1, Math.ceil(msUntilAvailable / weatherClientDayMs));
      setMatchWeather(null);
      setMatchWeatherStatus("unavailable");
      setMatchWeatherMessage(`Previsión del tiempo disponible en ${daysUntilAvailable} ${daysUntilAvailable === 1 ? "día" : "días"}.`);
      return;
    }

    const weatherCacheKey = `${activeMatch.id}:${matchDate.toISOString()}:${activeVenue.lat.toFixed(5)}:${activeVenue.lng.toFixed(5)}`;
    const cachedWeather = matchWeatherClientCache.get(weatherCacheKey);
    if (cachedWeather && cachedWeather.expiresAt > nowMs) {
      applyWeatherPayload(cachedWeather.payload);
      return;
    }

    const controller = new AbortController();
    const params = new URLSearchParams({
      at: matchDate.toISOString(),
      lat: String(activeVenue.lat),
      lng: String(activeVenue.lng),
    });
    const weatherClientCacheMs =
      msUntilMatch <= weatherForecastClientFreshWindowMs ? weatherClientShortCacheMs : weatherClientLongCacheMs;

    setMatchWeatherStatus("loading");
    setMatchWeatherMessage("");

    fetch(`/api/weather?${params.toString()}`, { signal: controller.signal })
      .then(async (response) => {
        const payload = await response.json();
        if (!response.ok) throw new Error(payload?.message ?? "No se pudo consultar la previsión.");
        return payload as WeatherApiPayload;
      })
      .then((payload) => {
        matchWeatherClientCache.set(weatherCacheKey, { expiresAt: Date.now() + weatherClientCacheMs, payload });
        applyWeatherPayload(payload);
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setMatchWeather(null);
        setMatchWeatherStatus("error");
        setMatchWeatherMessage(error instanceof Error ? error.message : "No se pudo consultar la previsión.");
      });

    return () => controller.abort();
  }, [activeMatch.date, activeMatch.id, activeVenue?.lat, activeVenue?.lng, isDemoMode, matchConfigured]);

  function updateMatch(next: Match) {
    setMatches((current) => current.map((match) => (match.id === next.id ? next : match)));
  }

  function clearAvatarDraft(playerId: string) {
    setAvatarDrafts((current) => {
      if (!current[playerId]) return current;
      const next = { ...current };
      delete next[playerId];
      return next;
    });
    if (avatarAdjustingPlayerId === playerId) setAvatarAdjustingPlayerId(null);
    avatarDragRef.current = null;
    setAvatarDragging(false);
  }

  function rememberPlayerProfileReturnTarget(scrollY: number | null = null) {
    profileReturnTargetRef.current = {
      matchPane: activeMatchManagerPane,
      mobileTab: activeMobileTab,
      profilePane,
      scrollY: scrollY ?? (activeMobileTab === "perfil" ? null : window.scrollY),
      teamGalleryOpen,
    };
  }

  function openPlayerProfile(playerId: string, options: { focusRating?: boolean } = {}) {
    rememberPlayerProfileReturnTarget();
    teamGalleryReturnScrollYRef.current = null;
    setMobileAccountOpen(false);
    setPlayerProfileMode("viewer");
    setProfilePane("ficha");
    setProfileFocusTarget(options.focusRating ? "rating" : null);
    setActiveMobileTab("perfil");
    setSelectedPlayerId(playerId);
    if (selectedPlayerId === playerId) {
      scrollToPlayerProfile();
    }
  }

  function openTeamGallery() {
    setMobileAccountOpen(false);
    setActiveMobileTab("equipo");
    setProfilePane("ranking");
    setTeamGalleryOpen(false);
    window.setTimeout(() => {
      window.requestAnimationFrame(() => {
        document.getElementById("ranking")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }, 0);
  }

  function openGroupSwitcher() {
    setActiveMobileTab("inicio");
    scrollToPanel(teamAccessPanelRef);
  }

  function openTeamGalleryPlayerProfile(playerId: string) {
    const returnScrollY = window.scrollY;
    teamGalleryReturnScrollYRef.current = returnScrollY;
    rememberPlayerProfileReturnTarget(returnScrollY);
    setMobileAccountOpen(false);
    setPlayerProfileMode("viewer");
    setProfilePane("ficha");
    setActiveMobileTab("perfil");
    setSelectedPlayerId(playerId);
    scrollToPlayerProfile();
  }

  function openRankingPanel() {
    setMobileAccountOpen(false);
    setProfilePane("ranking");
    setActiveMobileTab("equipo");
    setTeamGalleryOpen(false);
    window.setTimeout(() => {
      window.requestAnimationFrame(() => {
        document.getElementById("ranking")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }, 0);
  }

  function returnFromPlayerProfile() {
    if (selectedPlayerId) {
      clearAvatarDraft(selectedPlayerId);
      setAvatarMessage("");
    }
    setSelectedPlayerId(null);
    setPlayerProfileMode("edit");
    const returnTarget = profileReturnTargetRef.current;
    const nextTab = returnTarget && returnTarget.mobileTab !== "perfil" ? returnTarget.mobileTab : "inicio";
    const returnScrollY = returnTarget?.scrollY ?? teamGalleryReturnScrollYRef.current;
    profileReturnTargetRef.current = null;
    teamGalleryReturnScrollYRef.current = null;
    setActiveMatchManagerPane(returnTarget?.matchPane ?? activeMatchManagerPane);
    setProfilePane(returnTarget?.profilePane ?? (nextTab === "equipo" ? "ranking" : "ficha"));
    setTeamGalleryOpen(returnTarget?.teamGalleryOpen ?? false);
    lockMobileNavigationTab(nextTab);
    setActiveMobileTab(nextTab);

    window.setTimeout(() => {
      window.requestAnimationFrame(() => {
        if (returnScrollY !== null && returnScrollY !== undefined) {
          window.scrollTo({ behavior: "smooth", top: returnScrollY });
          return;
        }
        document.getElementById(nextTab)?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }, 0);
  }

  function closePlayerProfile() {
    returnFromPlayerProfile();
  }

  function scrollToPanel(ref: { current: HTMLElement | null }) {
    window.setTimeout(() => {
      window.requestAnimationFrame(() => {
        ref.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }, 0);
  }

  function scrollToPlayerProfile() {
    scrollToPanel(playerProfileRef);
  }

  function scrollToQuickForm(form: NonNullable<typeof openQuickForm>) {
    const targetRef = form === "venue" ? venueFormRef : teamFormRef;
    scrollToPanel(targetRef);
  }

  function lockMobileNavigationTab(tabId: MobileAppTab) {
    mobileNavigationLockRef.current = tabId;
    if (mobileNavigationUnlockTimerRef.current !== null) {
      window.clearTimeout(mobileNavigationUnlockTimerRef.current);
    }
    mobileNavigationUnlockTimerRef.current = window.setTimeout(() => {
      if (mobileNavigationLockRef.current === tabId) {
        mobileNavigationLockRef.current = null;
      }
    }, 1400);
  }

  function isMobileManagerLandscape() {
    const isLandscape = window.matchMedia("(orientation: landscape)").matches;
    if (!isLandscape) return false;

    const viewportWidth = Math.round(window.visualViewport?.width ?? window.innerWidth);
    const viewportHeight = Math.round(window.visualViewport?.height ?? window.innerHeight);
    const hasTouchInput =
      window.matchMedia("(pointer: coarse)").matches ||
      window.matchMedia("(any-pointer: coarse)").matches ||
      navigator.maxTouchPoints > 0;

    return viewportHeight <= 560 || (hasTouchInput && viewportWidth >= 768 && viewportWidth <= 1368 && viewportHeight <= 1024);
  }

  function navigateMobileTab(tabId: MobileSectionTabId) {
    lockMobileNavigationTab(tabId);
    setActiveMobileTab(tabId);
    const target = document.getElementById(tabId);
    target?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function navigatePrimaryMobile(tabId: MobileAppTab) {
    setCreateMenuOpen(false);
    setMobileAccountOpen(false);
    lockMobileNavigationTab(tabId);
    setActiveMobileTab(tabId);

    if (tabId === "mercado") {
      window.location.assign(canUseAdminControls && matchConfigured ? marketScoutUrl("jugadores") : "/mercado");
      return;
    }

    if (tabId === "partido") {
      const nextOpenMatch = openMatches[0];
      if (nextOpenMatch) setActiveMatchId(nextOpenMatch.id);
      setActiveMatchManagerPane("proximo");
      navigateMobileTab("partido");
      return;
    }

    const managerLandscape = isMobileManagerLandscape();

    if (tabId === "equipo") {
      setProfilePane("ranking");
      setTeamGalleryOpen(false);
      return;
    }

    if (tabId === "perfil") {
      if (managerLandscape) {
        rememberPlayerProfileReturnTarget();
        setMobileAccountOpen(false);
        setPlayerProfileMode("edit");
        setProfilePane("ficha");
        setSelectedPlayerId(ownPlayer?.id ?? selectedPlayerId ?? players[0]?.id ?? "");
        return;
      }
      setMobileAccountOpen(true);
      return;
    }

    navigateMobileTab(tabId);
  }

  function openMarketConfiguration() {
    setCreateMenuOpen(false);
    setMobileAccountOpen(false);
    lockMobileNavigationTab("mercado");
    setActiveMobileTab("mercado");
    window.setTimeout(() => {
      window.requestAnimationFrame(() => {
        document.getElementById("mercado")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }, 0);
  }

  function runMobileAccountAction(action: () => void) {
    setMobileAccountOpen(false);
    window.setTimeout(action, 80);
  }

  function showQuickForm(form: NonNullable<typeof openQuickForm>) {
    setActiveMobileTab("inicio");
    setOpenQuickForm(form);
    scrollToQuickForm(form);
  }

  function toggleSettingsPanel() {
    if (!canUseAdminControls) return;
    const nextShowSettings = !showSettings;
    if (nextShowSettings) setSettingsDraft(siteSettings);
    if (nextShowSettings) setActiveMobileTab("perfil");
    setShowSettings(nextShowSettings);
    if (nextShowSettings) scrollToPanel(settingsPanelRef);
  }

  function closeSettingsPanelWithoutSave() {
    setSettingsDraft(siteSettings);
    setShowSettings(false);
  }

  async function saveSettingsPanel() {
    if (!canUseAdminControls) {
      setShowSettings(false);
      return;
    }

    const nextSettings = normalizeSiteSettings(settingsDraft);
    const nextPayload: AppPayload = { activeMatchId, matches, players, siteSettings: nextSettings, venues };

    setSiteSettings(nextSettings);
    setSettingsDraft(nextSettings);
    localStorage.setItem(storageKey, serializeLocalPayloadCache(nextPayload, remoteGroupId ? "server-cache" : "local-draft"));

    const needsRemoteSave = Boolean(supabase && remoteGroupId && remoteReady && canManageTeam);
    if (needsRemoteSave) {
      const saved = await saveRemotePayload(nextPayload);
      if (!saved) return;
    }

    setShowSettings(false);
  }

  async function setGroupRatingsEnabled(nextEnabled: boolean) {
    if (!supabase || !remoteGroupId || !canManageTeam) return;

    setSyncStatus("connecting");
    setSyncError("");
    const result = await supabase.rpc("set_pachanga_group_ratings_enabled_authoritative_v2", {
      client_metadata: clientOperationMetadata(),
      expected_revision: remotePayloadRevisionRef.current,
      next_enabled: nextEnabled,
      operation_id: id(),
      target_group_id: remoteGroupId,
    });
    if (result.error) {
      markRemoteWriteError(result.error.message);
      return;
    }

    applyRemoteCommit(result.data as RemotePayloadCommit);
    setRatingEligibilityRevision((current) => current + 1);
  }

  function revealBillingPanel(message?: string) {
    if (message) setBillingMessage(message);
    setActiveMobileTab("perfil");
    setShowBillingPanel(true);
    scrollToPanel(billingPanelRef);
  }

  async function authAccessToken() {
    if (!supabase) throw new Error("Supabase no está configurado.");
    const sessionResult = await supabase.auth.getSession();
    const token = sessionResult.data.session?.access_token;
    if (!token) throw new Error("Entra con Google para gestionar pagos.");
    return token;
  }

  async function startBillingCheckout(interval: BillingInterval) {
    if (!remoteGroupId || !canManageBilling) {
      revealBillingPanel("Solo el owner del grupo puede activar la suscripción.");
      return;
    }

    setBillingLoading(interval);
    setBillingMessage("");

    try {
      const response = await clientWriteFetch("api:billing-checkout", "/api/billing/checkout", {
        body: JSON.stringify({ groupId: remoteGroupId, interval }),
        headers: {
          Authorization: `Bearer ${await authAccessToken()}`,
          "Content-Type": "application/json",
        },
        method: "POST",
      });
      const data = (await response.json()) as { error?: string; url?: string };
      if (!response.ok || !data.url) throw new Error(data.error ?? "No se pudo abrir Stripe.");
      window.location.href = data.url;
    } catch (error) {
      setBillingMessage(error instanceof Error ? error.message : "No se pudo abrir Stripe.");
      setBillingLoading(false);
    }
  }

  async function openBillingPortal() {
    if (!remoteGroupId || !canManageBilling) {
      revealBillingPanel("Solo el owner del grupo puede gestionar la suscripción.");
      return;
    }

    setBillingLoading("portal");
    setBillingMessage("");

    try {
      const response = await clientWriteFetch("api:billing-portal", "/api/billing/portal", {
        body: JSON.stringify({ groupId: remoteGroupId }),
        headers: {
          Authorization: `Bearer ${await authAccessToken()}`,
          "Content-Type": "application/json",
        },
        method: "POST",
      });
      const data = (await response.json()) as { error?: string; url?: string };
      if (!response.ok || !data.url) throw new Error(data.error ?? "No se pudo abrir el portal.");
      window.location.href = data.url;
    } catch (error) {
      setBillingMessage(error instanceof Error ? error.message : "No se pudo abrir el portal.");
      setBillingLoading(false);
    }
  }

  function runCreateAction(action: () => void) {
    setCreateMenuOpen(false);
    action();
  }

  function selectMatch(matchId: string) {
    setActiveMatchId(matchId);
    scrollToPanel(matchPanelRef);
  }

  function openMatchFromInicio(matchId: string, pane: MatchManagerPane = "proximo") {
    setActiveMatchId(matchId);
    setActiveMatchManagerPane(pane);
    navigateMobileTab("partido");
  }

  async function setStatus(playerId: string, status: MatchPlayer["status"], options?: { skipLeaveConfirmation?: boolean }) {
    const player = players.find((item) => item.id === playerId);
    const canChangeStatus = matchConfigured && registrationOpen && canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    if (!canChangeStatus) return;
    if (matchFinalized && !canUseAdminControls) return;
    if (status === "voy" && (player?.injured || player?.inactive)) return;
    const existing = activeMatch.players.find((entry) => entry.playerId === playerId);
    if (existing?.status === "voy" && status !== "voy" && !options?.skipLeaveConfirmation) {
      setPlayerActionMenu(null);
      setStatusConfirmation({ nextStatus: status, playerId });
      return;
    }

    if (supabase && remoteGroupId && hasRealTeam) {
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("patch_pachanga_match_player_status_authoritative_v2", {
        client_metadata: clientOperationMetadata(),
        expected_revision: remotePayloadRevisionRef.current,
        next_status: status,
        operation_id: id(),
        target_group_id: remoteGroupId,
        target_match_id: activeMatch.id,
        target_player_id: playerId,
      });

      if (result.error) {
        markRemoteWriteError(result.error.message);
        return;
      }

      applyRemoteCommit(result.data as RemotePayloadCommit);
      return;
    }

    const joinedAt = status === "voy" ? (existing?.status === "voy" ? existing.joinedAt : new Date().toISOString()) : undefined;
    const nextPlayers = existing
      ? activeMatch.players.map((entry) => (entry.playerId === playerId ? { ...entry, status, joinedAt, paid: status === "voy" ? entry.paid : false } : entry))
      : [...activeMatch.players, { playerId, status, joinedAt, paid: false }];
    const wasConfirmed = existing?.status === "voy";
    const willBeConfirmed = status === "voy";
    const previousGoals = activeMatch.scorers?.find((entry) => entry.playerId === playerId)?.goals ?? 0;
    const finalizedScoreA = activeMatch.scoreA ?? 0;
    const finalizedScoreB = activeMatch.scoreB ?? 0;
    const finalizedWinningIds = finalizedScoreA === finalizedScoreB ? [] : finalizedScoreA > finalizedScoreB ? activeMatch.teamA ?? [] : activeMatch.teamB ?? [];
    const nextMatch = {
      ...activeMatch,
      players: nextPlayers,
      scorers: matchFinalized && wasConfirmed && !willBeConfirmed ? activeMatch.scorers?.filter((entry) => entry.playerId !== playerId) : activeMatch.scorers,
    };

    updateMatch(nextMatch);

    if (matchFinalized && wasConfirmed !== willBeConfirmed) {
      const direction = willBeConfirmed ? 1 : -1;
      setPlayers((current) =>
        current.map((item) =>
          item.id === playerId
            ? {
                ...item,
                appearances: Math.max(0, item.appearances + direction),
                goals: Math.max(0, item.goals + direction * previousGoals),
                wins: Math.max(0, item.wins + (finalizedWinningIds.includes(playerId) ? direction : 0)),
              }
          : item,
        ),
      );
    }
  }

  function closeStatusConfirmation() {
    setStatusConfirmation(null);
  }

  function confirmStatusChange() {
    const pending = statusConfirmation;
    if (!pending) return;

    setStatusConfirmation(null);
    void setStatus(pending.playerId, pending.nextStatus, { skipLeaveConfirmation: true });
  }

  function setPlayerInjured(playerId: string, injured: boolean) {
    updatePlayer(playerId, { injured });
    if (!injured) return;

    setMatches((current) =>
      current.map((match) => {
        const existing = match.players.find((entry) => entry.playerId === playerId);
        if (!existing) return match;

        return {
          ...match,
          players: match.players.map((entry) =>
            entry.playerId === playerId
              ? { ...entry, status: "no", joinedAt: undefined, paid: false }
              : entry,
          ),
        };
      }),
    );
  }

  function deactivatePlayer(playerId: string) {
    if (!canUseAdminControls) return;
    const player = players.find((item) => item.id === playerId);
    if (!player) return;
    if (!window.confirm(`¿Eliminar a ${playerDisplayName(player)} del grupo?`)) return;
    if (!window.confirm("Confirmación final: conservará ranking e histórico, pero no podrá apuntarse.")) return;

    updatePlayer(playerId, { inactive: true, injured: false });
    setMatches((current) =>
      current.map((match) => {
        if (match.closed || match.scoreA !== undefined) return match;
        const existing = match.players.find((entry) => entry.playerId === playerId);
        if (!existing) return match;

        return {
          ...match,
          payerId: match.payerId === playerId ? undefined : match.payerId,
          players: match.players.map((entry) =>
            entry.playerId === playerId
              ? { ...entry, status: "no", joinedAt: undefined, paid: false }
              : entry,
          ),
          scorers: match.scorers?.filter((entry) => entry.playerId !== playerId),
          teamA: match.teamA?.filter((id) => id !== playerId),
          teamB: match.teamB?.filter((id) => id !== playerId),
        };
      }),
    );
  }

  async function togglePaid(playerId: string) {
    if (!matchConfigured) return;
    if (!paymentReady) return;
    const player = players.find((item) => item.id === playerId);
    const canChangePayment = canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    if (!canChangePayment) return;
    const existingEntry = activeMatch.players.find((entry) => entry.playerId === playerId);
    const nextPaid = !existingEntry?.paid;

    if (supabase && remoteGroupId && hasRealTeam) {
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("patch_pachanga_match_player_paid_authoritative_v2", {
        client_metadata: clientOperationMetadata(),
        expected_revision: remotePayloadRevisionRef.current,
        next_paid: nextPaid,
        operation_id: id(),
        target_group_id: remoteGroupId,
        target_match_id: activeMatch.id,
        target_player_id: playerId,
      });

      if (result.error) {
        markRemoteWriteError(result.error.message);
        return;
      }

      applyRemoteCommit(result.data as RemotePayloadCommit);
      return;
    }

    updateMatch({
      ...activeMatch,
      players: activeMatch.players.map((entry) => (entry.playerId === playerId ? { ...entry, paid: nextPaid } : entry)),
    });
  }

  function createMatch() {
    if (!canUseAdminControls) return;
    const existingDraft = matches.find((match) => !match.configured && !match.closed && match.scoreA === undefined);
    if (existingDraft) {
      selectMatch(existingDraft.id);
      return;
    }

    if (groupBillingLocked) {
      revealBillingPanel("Ya has finalizado los 2 partidos de prueba. Activa un plan para crear el siguiente.");
      return;
    }

    const defaultVenue = venues.find((venue) => venue.id === activeMatch.venueId) ?? venues[0];
    const nextKind = activeMatch.kind ?? defaultVenue?.kind ?? "futbol7";
    const nextDate = nextMatchDate(activeMatch.date);
    const next: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextDate,
      season: seasonKey(nextDate),
      place: defaultVenue?.name ?? "Campo por confirmar",
      configured: false,
      venueId: defaultVenue?.id,
      kind: nextKind,
      targetPlayers: matchKinds[nextKind].targetPlayers,
      fieldCost: activeMatch.fieldCost ?? defaultVenue?.defaultCost ?? 56,
      payerId: undefined,
      players: [],
      reservesAttend: activeMatch.reservesAttend ?? false,
      reserveLimit: activeMatch.reserveLimit ?? 0,
    };
    setMatches((current) => [next, ...current]);
    selectMatch(next.id);
  }

  async function toggleLineupClosed() {
    if (!canUseAdminControls) return;
    if (!registrationOpen) return;
    if (matchFinalized) return;
    const nextLineupClosed = !lineupClosed;
    const nextPayingIds = nextLineupClosed ? payingIds : [];
    const nextPayerId = nextLineupClosed
      ? activeMatch.payerId && nextPayingIds.includes(activeMatch.payerId)
        ? activeMatch.payerId
        : nextPayer(players, matches, activeMatch, nextPayingIds)
      : undefined;
    const nextMatch = {
      ...activeMatch,
      lineupClosed: nextLineupClosed,
      payerId: nextPayerId,
      publicOpen: nextLineupClosed ? false : activeMatch.publicOpen,
      teamA: suggested.teamA.map((player) => player.id),
      teamB: suggested.teamB.map((player) => player.id),
    };

    if (supabase && remoteGroupId && hasRealTeam) {
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("patch_pachanga_match_lineup_authoritative_v2", {
        client_metadata: clientOperationMetadata(),
        expected_revision: remotePayloadRevisionRef.current,
        next_lineup_closed: nextLineupClosed,
        operation_id: id(),
        target_group_id: remoteGroupId,
        target_match_id: activeMatch.id,
        target_payer_id: nextPayerId ?? null,
        target_team_a_ids: nextMatch.teamA ?? [],
        target_team_b_ids: nextMatch.teamB ?? [],
      });

      if (result.error) {
        markRemoteWriteError(result.error.message);
        return;
      }

      applyRemoteCommit(result.data as RemotePayloadCommit);
      return;
    }

    updateMatch(nextMatch);
    if (nextLineupClosed && activeMatch.publicOpen) {
      void syncOpenMatchPublication(nextMatch, false);
    }
  }

  function applyRandomTeams() {
    if (!canUseAdminControls) return;
    if (lineupClosed) return;
    if (matchFinalized) return;
    const next = randomTeams(confirmedPlayers);
    updateMatch({
      ...activeMatch,
      lineupSlots: undefined,
      teamA: next.teamA.map((player) => player.id),
      teamB: next.teamB.map((player) => player.id),
    });
  }

  function applyBalancedTeams() {
    if (!canUseAdminControls) return;
    if (lineupClosed) return;
    if (matchFinalized) return;
    updateMatch({
      ...activeMatch,
      lineupSlots: undefined,
      teamA: balancedLineup.teamA.map((player) => player.id),
      teamB: balancedLineup.teamB.map((player) => player.id),
    });
  }

  function swapLineupPlayers(sourcePlayerId: string, targetDropId: string) {
    const targetPlayerId = targetDropId.startsWith("player:") ? targetDropId.slice("player:".length) : targetDropId;
    if (sourcePlayerId === targetPlayerId) return;
    if (!canEditLineup) return;
    if (!registrationOpen) return;
    if (lineupClosed) return;
    if (matchFinalized) return;

    const slotCount = formationSlots(activeKind, "bottom").length;
    const nextTeamASlots = activeMatch.lineupSlots?.teamA?.length
      ? pitchSlotPlayerIds(suggested.teamA, activeMatch.lineupSlots.teamA, effectivePlayerScore, slotCount)
      : automaticPitchSlotPlayerIds(suggested.teamA, activeKind, "bottom", effectivePlayerScore);
    const nextTeamBSlots = activeMatch.lineupSlots?.teamB?.length
      ? pitchSlotPlayerIds(suggested.teamB, activeMatch.lineupSlots.teamB, effectivePlayerScore, slotCount)
      : automaticPitchSlotPlayerIds(suggested.teamB, activeKind, "bottom", effectivePlayerScore);
    const sourceSide = nextTeamASlots.includes(sourcePlayerId) ? "A" : nextTeamBSlots.includes(sourcePlayerId) ? "B" : null;
    if (!sourceSide) return;

    const sourceTeamSlots = sourceSide === "A" ? nextTeamASlots : nextTeamBSlots;
    const sourceIndex = sourceTeamSlots.indexOf(sourcePlayerId);
    if (sourceIndex < 0) return;

    if (targetDropId.startsWith("slot:")) {
      const [, targetSideValue, targetIndexValue] = targetDropId.split(":");
      const targetSide = targetSideValue === "A" || targetSideValue === "B" ? targetSideValue : null;
      const targetIndex = Number(targetIndexValue);
      if (!targetSide || !Number.isInteger(targetIndex) || targetIndex < 0 || targetIndex >= slotCount) return;
      const targetTeamSlots = targetSide === "A" ? nextTeamASlots : nextTeamBSlots;
      if (targetTeamSlots[targetIndex] === sourcePlayerId) return;
      sourceTeamSlots[sourceIndex] = targetTeamSlots[targetIndex] ?? null;
      targetTeamSlots[targetIndex] = sourcePlayerId;
    } else {
      const targetSide = nextTeamASlots.includes(targetPlayerId) ? "A" : nextTeamBSlots.includes(targetPlayerId) ? "B" : null;
      if (!targetSide) return;
      const targetTeamSlots = targetSide === "A" ? nextTeamASlots : nextTeamBSlots;
      const targetIndex = targetTeamSlots.indexOf(targetPlayerId);
      if (targetIndex < 0) return;

      sourceTeamSlots[sourceIndex] = targetPlayerId;
      targetTeamSlots[targetIndex] = sourcePlayerId;
    }

    const nextTeamA = compactLineupSlotIds(nextTeamASlots);
    const nextTeamB = compactLineupSlotIds(nextTeamBSlots);

    updateMatch({
      ...activeMatch,
      lineupSlots: {
        teamA: trimLineupSlots(nextTeamASlots),
        teamB: trimLineupSlots(nextTeamBSlots),
      },
      teamA: nextTeamA,
      teamB: nextTeamB,
    });
  }

  function assignPlayerTeam(playerId: string, team: "A" | "B") {
    if (!canUseAdminControls) return;
    if (lineupClosed) return;
    if (matchFinalized) return;
    const baseTeamA = pitchOrderedPlayerIds(suggested.teamA, activeMatch.lineupSlots?.teamA, effectivePlayerScore).filter((id) => id !== playerId);
    const baseTeamB = pitchOrderedPlayerIds(suggested.teamB, activeMatch.lineupSlots?.teamB, effectivePlayerScore).filter((id) => id !== playerId);
    const nextTeamA = team === "A" ? [...baseTeamA, playerId] : baseTeamA;
    const nextTeamB = team === "B" ? [...baseTeamB, playerId] : baseTeamB;

    updateMatch({
      ...activeMatch,
      lineupSlots: {
        teamA: nextTeamA,
        teamB: nextTeamB,
      },
      teamA: nextTeamA,
      teamB: nextTeamB,
    });
  }

  async function setPlayerGoals(playerId: string, goals: number) {
    if (!canUseAdminControls) return;
    if (!resultIsReady) return;

    const scorers = activeMatch.scorers ?? [];
    const isTeamA = suggested.teamA.some((player) => player.id === playerId);
    const teamPlayers = isTeamA ? suggested.teamA : suggested.teamB;
    const teamLimit = Number(isTeamA ? scoreAValue : scoreBValue);
    const currentOtherGoals = teamPlayers.reduce(
      (sum, player) => sum + (player.id === playerId ? 0 : scorers.find((entry) => entry.playerId === player.id)?.goals ?? 0),
      0,
    );
    const nextGoals = Math.max(0, Math.min(goals, Math.max(teamLimit - currentOtherGoals, 0)));
    const existing = scorers.find((entry) => entry.playerId === playerId);
    const nextScorers = existing
      ? scorers.map((entry) => (entry.playerId === playerId ? { ...entry, goals: nextGoals } : entry))
      : [...scorers, { playerId, goals: nextGoals }];
    const cleanScorers = nextScorers.filter((entry) => entry.goals > 0);
    const goalDelta = nextGoals - (existing?.goals ?? 0);

    if (supabase && remoteGroupId && hasRealTeam && canUseAdminControls) {
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("patch_pachanga_match_scorers_authoritative_v2", {
        client_metadata: clientOperationMetadata(),
        expected_revision: remotePayloadRevisionRef.current,
        next_scorers: cleanScorers,
        operation_id: id(),
        target_group_id: remoteGroupId,
        target_match_id: activeMatch.id,
        target_score_a: Number(scoreAValue),
        target_score_b: Number(scoreBValue),
        target_team_a_ids: suggested.teamA.map((player) => player.id),
        target_team_b_ids: suggested.teamB.map((player) => player.id),
      });

      if (result.error) {
        markRemoteWriteError(result.error.message);
        return;
      }

      applyRemoteCommit(result.data as RemotePayloadCommit);
      return;
    }

    updateMatch({
      ...activeMatch,
      scorers: cleanScorers,
    });

    if (matchFinalized && goalDelta !== 0) {
      setPlayers((current) =>
        current.map((player) => (player.id === playerId ? { ...player, goals: Math.max(0, player.goals + goalDelta) } : player)),
      );
    }
  }

  function scorerRows(teamPlayers: Player[], variant: "team-a" | "team-b") {
    const teamLimit = Number(variant === "team-a" ? scoreAValue : scoreBValue);
    const assignedTeamGoals = teamPlayers.reduce(
      (sum, teamPlayer) => sum + (activeMatch.scorers?.find((entry) => entry.playerId === teamPlayer.id)?.goals ?? 0),
      0,
    );
    const teamHasNoGoals = resultIsReady && teamLimit === 0;
    const teamGoalsComplete = resultIsReady && assignedTeamGoals >= teamLimit;

    return teamPlayers
      .map((player) => {
        const goals = activeMatch.scorers?.find((entry) => entry.playerId === player.id)?.goals ?? 0;
        if (!resultIsReady || (teamHasNoGoals && goals === 0) || (teamGoalsComplete && goals === 0)) return null;

        return (
          <div className={`scorer-row ${variant}-row`} key={player.id}>
            <span>
              {player.inactive ? (
                <span className="inline-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                  <UserOffLogo />
                </span>
              ) : null}
              {player.injured ? (
                <span className="inline-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                  <HospitalLogo />
                </span>
              ) : null}
              {playerDisplayName(player)}
            </span>
            <button type="button" disabled={goals === 0} onClick={() => void setPlayerGoals(player.id, goals - 1)}>-</button>
            <b>{goals}</b>
            <button type="button" disabled={!resultIsReady || assignedTeamGoals >= teamLimit} onClick={() => void setPlayerGoals(player.id, goals + 1)}>+</button>
          </div>
        );
      })
      .filter(Boolean);
  }

  async function finalizeMatch() {
    if (!canUseAdminControls) return;
    if (matchFinalized) return;
    if (!resultIsReady) return;
    if (!lineupClosed) return;
    if (groupBillingLocked) {
      revealBillingPanel("La prueba gratuita ya ha cerrado 2 partidos. Activa un plan para finalizar más partidos.");
      return;
    }

    const scoreA = Number(scoreAValue);
    const scoreB = Number(scoreBValue);
    const winners = scoreA === scoreB ? [] : scoreA > scoreB ? suggested.teamA.map((player) => player.id) : suggested.teamB.map((player) => player.id);
    const previousGoalsByPlayer = new Map((activeMatch.scorers ?? []).map((entry) => [entry.playerId, entry.goals]));
    const shouldApplyMatchStats = !activeMatch.closed;

    const nextPlayers = players.map((player) =>
      confirmedIds.includes(player.id)
        ? {
            ...player,
            appearances: shouldApplyMatchStats ? player.appearances + 1 : player.appearances,
            goals: shouldApplyMatchStats ? player.goals + (previousGoalsByPlayer.get(player.id) ?? 0) : player.goals,
            wins: shouldApplyMatchStats && winners.includes(player.id) ? player.wins + 1 : player.wins,
          }
        : player,
    );
    const nextMatch = {
      ...activeMatch,
      scoreA,
      scoreB,
      closed: true,
      payerId,
      season: seasonKey(activeMatch.date),
      teamA: suggested.teamA.map((player) => player.id),
      teamB: suggested.teamB.map((player) => player.id),
    };
    const nextMatches = matches.map((match) => (match.id === activeMatch.id ? nextMatch : match));
    const nextPayload = { activeMatchId, matches: nextMatches, players: nextPlayers, siteSettings, venues };

    if (supabase && remoteGroupId && hasRealTeam) {
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("finalize_pachanga_match_authoritative_v2", {
        client_metadata: clientOperationMetadata(),
        expected_revision: remotePayloadRevisionRef.current,
        operation_id: id(),
        target_group_id: remoteGroupId,
        target_match_id: activeMatch.id,
        target_score_a: scoreA,
        target_score_b: scoreB,
        target_scorers: activeMatch.scorers ?? [],
      });

      if (result.error) {
        const message = result.error.message;
        if (message.toLowerCase().includes("trial limit")) {
          revealBillingPanel("La prueba gratuita ya ha cerrado 2 partidos. Activa un plan para finalizar más partidos.");
          setSyncStatus("live");
          setSyncError("");
          return;
        }

        markRemoteWriteError(message);
        if (isRemoteRevisionConflict(message)) {
          await loadTeams(supabase, remoteGroupId).catch((error) => {
            setSyncError(error instanceof Error ? error.message : "No se pudo recargar el grupo");
          });
        }
        return;
      }

      const commit = result.data as RemotePayloadCommit;
      applyRemoteCommit(commit);
      await createTeamBackup(
        "partido_finalizado",
        normalizePayload((commit.payload ?? nextPayload) as Partial<AppPayload>),
        false,
      );
      return;
    }

    setPlayers(nextPlayers);
    setMatches(nextMatches);
    await saveRemotePayloadWithBackup(nextPayload, "partido_finalizado");
  }

  function deleteClosedMatch(matchId: string) {
    if (!canUseAdminControls) return;
    const match = matches.find((item) => item.id === matchId);
    if (!match) return;

    const confirmedMatchIds = match.players.filter((entry) => entry.status === "voy").map((entry) => entry.playerId);
    const scoreA = match.scoreA ?? 0;
    const scoreB = match.scoreB ?? 0;
    const winningIds = scoreA === scoreB ? [] : scoreA > scoreB ? match.teamA ?? [] : match.teamB ?? [];
    const goalsByPlayer = new Map((match.scorers ?? []).map((entry) => [entry.playerId, entry.goals]));

    setPlayers((current) =>
      current.map((player) =>
        confirmedMatchIds.includes(player.id)
          ? {
              ...player,
              appearances: Math.max(0, player.appearances - 1),
              goals: Math.max(0, player.goals - (goalsByPlayer.get(player.id) ?? 0)),
              wins: Math.max(0, player.wins - (winningIds.includes(player.id) ? 1 : 0)),
            }
          : player,
      ),
    );

    const remainingMatches = matches.filter((item) => item.id !== matchId);
    const fallbackKind = match.kind ?? "futbol7";
    const fallbackVenue = venues.find((venue) => venue.id === match.venueId) ?? venues[0];
    const replacementDate = nextMatchDate(match.date);
    const replacementMatch: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: replacementDate,
      season: seasonKey(replacementDate),
      place: fallbackVenue?.name ?? "Campo por confirmar",
      venueId: fallbackVenue?.id,
      kind: fallbackKind,
      targetPlayers: matchKinds[fallbackKind].targetPlayers,
      fieldCost: match.fieldCost ?? fallbackVenue?.defaultCost ?? 56,
      players: [],
      reservesAttend: match.reservesAttend ?? false,
      reserveLimit: match.reserveLimit ?? 0,
    };
    const nextMatches = remainingMatches.length > 0 ? remainingMatches : [replacementMatch];
    const nextActiveMatchId = activeMatchId === matchId ? nextMatches[0].id : activeMatchId;

    setActiveMatchId(nextActiveMatchId);
    setMatches(nextMatches);
  }

  function deleteMatch(matchId: string) {
    if (!canUseAdminControls) return;
    const match = matches.find((item) => item.id === matchId);
    if (!match) return;
    if (!window.confirm("¿Borrar este partido?")) return;
    if (!window.confirm("Confirmación final: se eliminará definitivamente.")) return;

    if (match.scoreA !== undefined || match.closed) {
      deleteClosedMatch(matchId);
      return;
    }

    const remainingMatches = matches.filter((item) => item.id !== matchId);
    const fallbackKind = match.kind ?? "futbol7";
    const fallbackVenue = venues.find((venue) => venue.id === match.venueId) ?? venues[0];
    const replacementDate = nextMatchDate(match.date);
    const replacementMatch: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: replacementDate,
      season: seasonKey(replacementDate),
      place: fallbackVenue?.name ?? "Campo por confirmar",
      venueId: fallbackVenue?.id,
      kind: fallbackKind,
      targetPlayers: matchKinds[fallbackKind].targetPlayers,
      fieldCost: match.fieldCost ?? fallbackVenue?.defaultCost ?? 56,
      players: [],
      reservesAttend: match.reservesAttend ?? false,
      reserveLimit: match.reserveLimit ?? 0,
    };
    const nextMatches = remainingMatches.length > 0 ? remainingMatches : [replacementMatch];
    const nextActiveMatchId = activeMatchId === matchId ? nextMatches[0].id : activeMatchId;

    setActiveMatchId(nextActiveMatchId);
    setMatches(nextMatches);
  }

  const activeMatchSeason = matchSeason(activeMatch);
  const rankingSeasons = useMemo(() => {
    const seasons = new Set<string>([seasonKey(new Date()), activeMatchSeason]);
    matches.forEach((match) => seasons.add(matchSeason(match)));
    return [...seasons].sort((a, b) => seasonStartYear(b) - seasonStartYear(a));
  }, [activeMatchSeason, matches]);
  const activeRankingSeason = rankingSeasons.includes(rankingSeason) ? rankingSeason : rankingSeasons[0] ?? rankingSeason;
  const activeHistorySeason = historySeason === "all" || rankingSeasons.includes(historySeason) ? historySeason : "all";
  const filteredClosedMatches =
    activeHistorySeason === "all" ? closedMatches : closedMatches.filter((match) => matchSeason(match) === activeHistorySeason);
  const rankedPlayers = useMemo(() => {
    const stats = new Map(
      players.map((player) => [
        player.id,
        {
          appearances: 0,
          balanceScore: effectivePlayerScore(player),
          form: playerForm(player),
          goals: 0,
          media: playerMediaScore(player),
          player,
          wins: 0,
        },
      ]),
    );

    matches
      .filter((match) => match.scoreA !== undefined && matchSeason(match) === activeRankingSeason)
      .forEach((match) => {
        const playedIds = new Set(matchPlayingIds(match));
        const winningIds = new Set(
          match.scoreA === match.scoreB ? [] : (match.scoreA ?? 0) > (match.scoreB ?? 0) ? match.teamA ?? [] : match.teamB ?? [],
        );

        playedIds.forEach((playerId) => {
          const row = stats.get(playerId);
          if (!row) return;
          row.appearances += 1;
          if (winningIds.has(playerId)) row.wins += 1;
        });

        (match.scorers ?? []).forEach((entry) => {
          const row = stats.get(entry.playerId);
          if (!row) return;
          row.goals += entry.goals;
        });
      });

    const rankingValue = (row: { appearances: number; goals: number; media: number; wins: number }) => {
      if (rankingSort === "goles") return row.goals;
      if (rankingSort === "partidos") return row.appearances;
      if (rankingSort === "ganados") return row.wins;
      return row.media;
    };

    return [...stats.values()].sort((a, b) =>
      rankingValue(b) - rankingValue(a) ||
      b.media - a.media ||
      b.goals - a.goals ||
      b.wins - a.wins ||
      b.appearances - a.appearances ||
      playerDisplayName(a.player).localeCompare(playerDisplayName(b.player), "es"),
    );
  }, [activeRankingSeason, matches, players, rankingSort, playerForms]);
  const rankingBadgeText = (row: (typeof rankedPlayers)[number]) => {
    if (rankingSort === "goles") return `${row.goals} ${row.goals === 1 ? "gol" : "goles"}`;
    if (rankingSort === "partidos") return `${row.appearances} PJ`;
    if (rankingSort === "ganados") return `${row.wins} ${row.wins === 1 ? "victoria" : "victorias"}`;
    return `Media ${overallScore(row.media)}`;
  };
  const sortedPlayers = [...players].sort((a, b) => {
    const statusOrder: Record<MatchPlayer["status"] | "sin", number> = { voy: 0, duda: 1, no: 2, sin: 3 };
    const statusA = a.injured || a.inactive ? "no" : activeMatch.players.find((entry) => entry.playerId === a.id)?.status ?? "sin";
    const statusB = b.injured || b.inactive ? "no" : activeMatch.players.find((entry) => entry.playerId === b.id)?.status ?? "sin";
    return statusOrder[statusA] - statusOrder[statusB] || a.name.localeCompare(b.name, "es");
  });
  const teamGalleryPlayers = [...players].sort((a, b) => Number(Boolean(a.inactive)) - Number(Boolean(b.inactive)) || playerDisplayName(a).localeCompare(playerDisplayName(b), "es"));
  const teamAPlayerIds = new Set(suggested.teamA.map((player) => player.id));
  const teamBPlayerIds = new Set(suggested.teamB.map((player) => player.id));
  const reservePlayerIds = new Set(reserveIds);
  const waitingPlayerIds = new Set(waitingIds);
  const sortedTeamA = sortedLineupPlayers(suggested.teamA, effectivePlayerScore);
  const sortedTeamB = sortedLineupPlayers(suggested.teamB, effectivePlayerScore);
  const otherPlayers = registrationOpen
    ? sortedPlayers.filter((player) => !player.inactive && !teamAPlayerIds.has(player.id) && !teamBPlayerIds.has(player.id) && !reservePlayerIds.has(player.id) && !waitingPlayerIds.has(player.id))
    : [];
  const doubtfulOtherPlayers = otherPlayers.filter((player) => !player.injured && !player.inactive && activeMatch.players.find((entry) => entry.playerId === player.id)?.status === "duda");
  const notGoingPlayers = otherPlayers.filter((player) => !player.injured && !player.inactive && activeMatch.players.find((entry) => entry.playerId === player.id)?.status === "no");
  const silentPlayers = otherPlayers.filter((player) => !player.injured && !player.inactive && !activeMatch.players.some((entry) => entry.playerId === player.id));
  const injuredOtherPlayers = otherPlayers.filter((player) => player.injured);
  const nextMatchStatusGroups = [
    { id: "duda", title: "Duda", players: doubtfulOtherPlayers },
    { id: "no", title: "No van", players: notGoingPlayers },
    { id: "sin", title: "Sin respuesta", players: silentPlayers },
    { id: "lesionados", title: "Lesionados", players: injuredOtherPlayers },
  ].filter((group) => group.players.length > 0);
  const nextMatchStatusCount = nextMatchStatusGroups.reduce((total, group) => total + group.players.length, 0);
  const showReserveRosterColumn = matchFinalized
    ? Boolean(activeMatch.reservesAttend && reservePlayers.length > 0)
    : Boolean(activeMatch.reservesAttend || reservePlayers.length > 0);
  const showWaitingRosterColumn = !matchFinalized && waitingPlayers.length > 0;
  const showStatusRosterColumn = !matchFinalized;
  const selectedPlayer = selectedPlayerId ? players.find((player) => player.id === selectedPlayerId) : undefined;
  const selectedRatingFacets = selectedPlayer ? ratingFacetsForPlayer(selectedPlayer) : ratingFacets;
  const selectedForm = selectedPlayer ? playerForm(selectedPlayer) : undefined;
  const selectedEffectiveScore = selectedPlayer ? effectivePlayerScore(selectedPlayer) : 0;
  const selectedPeerScore = selectedPlayer ? peerAverage(selectedPlayer) : 0;
  const selectedPlayerAge = selectedPlayer ? playerAge(selectedPlayer.birthDate, currentDateValue) : null;
  const selectedMarketZones = selectedPlayer ? normalizeMarketZonesGeo(selectedPlayer.marketZonesGeo) : [];
  const selectedMarketAvailabilitySlots = selectedPlayer ? marketAvailabilitySlots(selectedPlayer.marketAvailability) : [];
  const selectedMarketReady = selectedPlayer ? playerMarketProfileComplete(selectedPlayer) : true;
  const currentTeam = remoteTeams.find((team) => team.id === remoteGroupId);
  const ratingsEnabled = isDemoMode || currentTeam?.ratingsEnabled !== false;
  const isRegisteredUser = Boolean(authUser && !isAnonymousAuthUser(authUser));
  const hasRealTeam = !previewDemoMode && remoteReady && Boolean(remoteGroupId);
  const billingActive = teamBillingIsActive(currentTeam);
  const billingTrialUsed = Math.max(0, currentTeam?.billingTrialFinalizedMatches ?? 0);
  const billingTrialRemaining = Math.max(0, freeTrialMatchLimit - billingTrialUsed);
  const groupBillingLocked = Boolean(hasRealTeam && !billingActive && billingTrialUsed >= freeTrialMatchLimit);
  const actualCanManageBilling = Boolean(hasRealTeam && isRegisteredUser && currentRole === "owner");
  const actualCanManageTeam = Boolean(hasRealTeam && isRegisteredUser && (currentRole === "owner" || currentRole === "admin"));
  const canPreviewPlayerView = isDemoMode || actualCanManageTeam;
  const playerPreviewActive = canPreviewPlayerView && previewRequested;
  const canManageBilling = actualCanManageBilling && !playerPreviewActive;
  const ownerContributionPlayer = players.find((player) => currentTeam?.ownerId && player.ownerUserId === currentTeam.ownerId);
  const ownerContributionRecipient = ownerContributionPlayer ? playerDisplayName(ownerContributionPlayer) : "owner del grupo";
  const showSubscriptionPanel = Boolean(hasRealTeam && !playerPreviewActive && (showBillingPanel || groupBillingLocked || (showSettings && currentRole === "owner")));
  const needsLoginForSharedLink = hasIncomingSharedLink && !isRegisteredUser && !hasRealTeam;
  const sharedLinkContentBlocked = needsLoginForSharedLink || sharedMatchAccessDenied;
  const canManageTeam = actualCanManageTeam && !playerPreviewActive;
  const canManageRoles = actualCanManageBilling && !playerPreviewActive;
  const canUseAdminControls = canPreviewPlayerView && !playerPreviewActive;
  const displayedRole: MemberRole | null = playerPreviewActive ? "player" : currentRole;
  const mainPanelClassName = [
    canUseAdminControls ? "panel main-panel" : "panel main-panel player-facing-main",
    matchFinalized ? "match-finalized-main" : "",
  ].filter(Boolean).join(" ");
  const matchManagerPanes: MatchManagerPane[] = canUseAdminControls
    ? ["proximo", "alineacion", "resultado", "admin"]
    : ["proximo", "alineacion", "resultado"];
  const selectedMatchManagerPane = matchManagerPanes.includes(activeMatchManagerPane) ? activeMatchManagerPane : "proximo";
  const matchManagerPaneLabel = (pane: MatchManagerPane) => (pane === "proximo" && matchFinalized ? "Histórico" : matchManagerPaneLabels[pane]);
  const canConfigureMatchMarket = canUseAdminControls && showMatchRoster && !lineupClosed && !matchFinalized;
  const canCreateTeam = Boolean(supabase && isRegisteredUser);
  const ownPlayer = currentUserId ? players.find((player) => player.ownerUserId === currentUserId) : undefined;
  const needsOwnPlayerProfile = hasRealTeam && isRegisteredUser && !ownPlayer;
  const playerImportCandidates = useMemo(
    () => importCandidatesForUser(remoteTeams, remoteGroupId, currentUserId),
    [remoteTeams, remoteGroupId, currentUserId],
  );
  const defaultPlayerImportCandidate = playerImportCandidates.find((candidate) => !candidate.inactive) ?? playerImportCandidates[0];
  const selectedImportCandidate =
    playerImportCandidates.find((candidate) => candidate.key === selectedImportCandidateKey) ??
    defaultPlayerImportCandidate;
  const showPlayerImportGate = Boolean(needsOwnPlayerProfile && playerImportCandidates.length > 0);
  const needsProfileForSharedMatch = hasRealTeam && isRegisteredUser && incomingSharedLink.hasMatch && !ownPlayer && !showPlayerImportGate;
  const googleButtonText = needsLoginForSharedLink ? "Continuar con Google y volver" : "Continuar con Google";
  const selectedPlayerIsOwn = Boolean(selectedPlayer?.ownerUserId && selectedPlayer.ownerUserId === currentUserId);
  const canEditSelectedPlayer = canEditPlayerOwnedFields({
    canUseAdminControls,
    currentUserId,
    hasRealTeam,
    isDemoMode: isDemoMode && !playerPreviewActive,
    isRegisteredUser,
    player: selectedPlayer,
  });
  const selectedAvatarDraft = selectedPlayer ? avatarDrafts[selectedPlayer.id] : undefined;
  const selectedAvatarPreview = selectedAvatarDraft?.avatar ?? selectedPlayer?.avatar;
  const canAdjustSelectedAvatar = Boolean(canEditSelectedPlayer && selectedPlayer && selectedAvatarDraft && avatarAdjustingPlayerId === selectedPlayer.id);
  const showPlayerSwitcher = Boolean(playerProfileMode === "edit" && canUseAdminControls && selectedPlayer && !selectedPlayerIsOwn && players.length > 1);

  useEffect(() => {
    if (!selectedPlayerIsOwn || !selectedPlayer?.marketEnabled) {
      setMarketZoneDraft("");
      setMarketZonePlaceMessage("");
      setMarketZonePlaceStatus("idle");
      return;
    }

    if (!googleMapsApiKey) {
      setMarketZonePlaceStatus("missing-key");
      return;
    }

    const input = marketZoneInputRef.current;
    if (!input) return;

    let cleanup: (() => void) | undefined;
    let disposed = false;
    setMarketZonePlaceStatus("loading");

    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input,
      onPlace: (place) => {
        if (disposed || !selectedPlayer) return;
        const nextZones = appendMarketZoneGeo(selectedPlayer.marketZonesGeo, place, marketZoneRadiusKm);
        updatePlayer(selectedPlayer.id, {
          marketZones: marketZoneTextFromGeo(nextZones),
          marketZonesGeo: nextZones,
        });
        setMarketZoneDraft("");
        setMarketZonePlaceMessage("");
      },
      types: ["(cities)"],
    })
      .then((nextCleanup) => {
        if (disposed) {
          nextCleanup();
          return;
        }
        cleanup = nextCleanup;
        setMarketZonePlaceStatus("ready");
      })
      .catch((error: unknown) => {
        if (disposed) return;
        setMarketZonePlaceStatus("error");
        setMarketZonePlaceMessage(error instanceof Error ? error.message : "No se pudo cargar Google Places.");
      });

    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [marketZoneRadiusKm, selectedPlayer?.id, selectedPlayer?.marketEnabled, selectedPlayer?.marketZonesGeo, selectedPlayerIsOwn]);
  const showGroupAccessPanel = isRegisteredUser && canUseAdminControls;
  const showTeamAdminPanel = canManageTeam;
  const showMatchAdminPanel = canUseAdminControls;
  const canEditMatchSettings = canUseAdminControls && !matchFinalized;
  const canEditLineup = canUseAdminControls && registrationOpen && !lineupClosed && !matchFinalized;
  const canToggleLineupFromContext = canUseAdminControls && matchConfigured && registrationOpen && !matchFinalized;

  function toggleAdminPlayerView() {
    if (!previewRequested) {
      setCreateMenuOpen(false);
      setOpenQuickForm(null);
      setRewardBoxDemoOpen(false);
      setShowBillingPanel(false);
      setShowSettings(false);
    }
    toggleAdminViewPreview();
  }
  const canUploadTeamPhoto = Boolean(matchConfigured && (isDemoMode || hasRealTeam) && !needsLoginForSharedLink);
  const matchCanBeSaved = Boolean(
    canUseAdminControls &&
      !matchFinalized &&
      activeMatch.venueId &&
      activeMatch.date &&
      activeMatch.kind &&
      Number.isFinite(fieldCost) &&
      fieldCost >= 0 &&
      !groupBillingLocked,
  );

  useEffect(() => {
    void loadOpenMatchRequests();
  }, [activeMatch.id, canUseAdminControls, remoteGroupId, remoteReady]);

  useEffect(() => {
    if (!supabase || !remoteGroupId || !remoteReady || !canUseAdminControls) return;

    const client = supabase;
    const channel = client
      .channel(`pachanga-open-requests-${remoteGroupId}-${activeMatch.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_open_match_requests", filter: `source_group_id=eq.${remoteGroupId}` },
        (payload) => {
          const row = (payload.new ?? payload.old) as { source_match_id?: string } | null;
          if (!row || row.source_match_id === activeMatch.id) void loadOpenMatchRequests(client, remoteGroupId, activeMatch.id);
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [activeMatch.id, canUseAdminControls, remoteGroupId, remoteReady]);

  useEffect(() => {
    if (!showPlayerImportGate || !defaultPlayerImportCandidate) {
      setSelectedImportCandidateKey(null);
      setShowImportChoices(false);
      return;
    }

    const selectedStillExists = playerImportCandidates.some((candidate) => candidate.key === selectedImportCandidateKey);
    if (!selectedImportCandidateKey || !selectedStillExists) {
      setSelectedImportCandidateKey(defaultPlayerImportCandidate.key);
    }
  }, [defaultPlayerImportCandidate?.key, playerImportCandidates, selectedImportCandidateKey, showPlayerImportGate]);

  useEffect(() => {
    if (needsLoginForSharedLink) return;
    if (isMobileManagerLandscape()) return;
    if (window.matchMedia("(max-width: 760px)").matches) return;

    const sections = mobileNavigationTabs
      .map((tab) => document.getElementById(tab.id))
      .filter((section): section is HTMLElement => Boolean(section));

    if (sections.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (mobileNavigationLockRef.current) return;
        if (isMobileManagerLandscape()) return;

        const visibleEntry = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

        const visibleId = visibleEntry?.target.id as MobileSectionTabId | undefined;
        if (visibleId) setActiveMobileTab(visibleId);
      },
      {
        rootMargin: "-18% 0px -58% 0px",
        threshold: [0.04, 0.18, 0.34, 0.5, 0.72],
      },
    );

    sections.forEach((section) => observer.observe(section));
    return () => observer.disconnect();
  }, [needsLoginForSharedLink, selectedPlayerId, teamGalleryOpen]);

  const ratingVoterId = currentUserId ?? `local:${profileName.trim().toLocaleLowerCase("es-ES") || "jugador"}`;
  const selectedRatingRole = selectedPlayer ? ratingRoleForPlayer(selectedPlayer) : "field";
  const selectedRatingHistory = selectedPlayer ? ratingHistory(selectedPlayer, selectedRatingRole) : [];
  const selectedRatingChartHistory = selectedRatingHistory.slice(-10);
  const canRateSelectedPlayer = Boolean(
    ratingsEnabled &&
    ratingEligibility?.canRate &&
      selectedPlayer &&
      !selectedPlayerIsOwn &&
      (isDemoMode || (hasRealTeam && isRegisteredUser)),
  );
  const ratingSharedMatches = Math.min(ratingEligibility?.sharedMatches ?? 0, ratingEligibility?.requiredMatches ?? 3);
  const ratingWaitMatches = Math.max(0, (ratingEligibility?.requiredMatches ?? 0) - (ratingEligibility?.sharedMatches ?? 0));
  const selectedRatingStatusText = selectedPlayer
    ? selectedPlayer.inactive
      ? "Jugador fuera del grupo: valoración bloqueada."
      : !ratingsEnabled
        ? "Las valoraciones están desactivadas para este grupo."
      : selectedPlayer.goalkeeperOnly
        ? "La valoración específica de porteros está pendiente. Sus facetas antiguas se conservan como legado."
      : selectedPlayerIsOwn
        ? "No puedes votar tu propia ficha."
        : hasRealTeam && !isRegisteredUser
          ? "Entra con Google para valorar a compañeros."
          : ratingEligibilityLoading
            ? "Comprobando si puedes valorar..."
            : ratingEligibility?.canRate
              ? ratingEligibility.firstRating
                ? "Primera valoración disponible. No necesitas haber jugado antes con esta persona."
                : "Ya habéis compartido 3 partidos nuevos. Esta valoración sustituirá a la anterior."
              : ratingEligibility?.reason === "target_not_current_member"
                ? "Solo puedes valorar a miembros activos de este grupo."
                : `Progreso para volver a valorar: ${ratingSharedMatches}/3. Faltan ${ratingWaitMatches}.`
    : "";
  const selectedRatingButtonText = canRateSelectedPlayer
    ? ratingEligibility?.firstRating ? "Guardar primera valoración" : "Sustituir valoración anterior"
    : ratingWaitMatches > 0
      ? `${ratingWaitMatches === 1 ? "Falta" : "Faltan"} ${ratingWaitMatches} partido${ratingWaitMatches === 1 ? "" : "s"} para abrir votaciones`
      : "Valoraciones cerradas";
  const playerAssessmentInitialResult = useMemo(() => {
    if (!playerAssessment) return null;
    try {
      return calculateInitialRatings(playerAssessment.initial);
    } catch {
      return null;
    }
  }, [playerAssessment]);
  const playerAssessmentApplicableAdvancedQuestions = useMemo(
    () => playerAssessmentInitialResult ? calculateApplicableAdvancedQuestions(playerAssessmentInitialResult) : [],
    [playerAssessmentInitialResult],
  );
  const playerAssessmentAdvancedStepCount = Math.max(1, playerAssessmentApplicableAdvancedQuestions.length);
  const playerAssessmentAdvancedQuestion = playerAssessment
    ? playerAssessmentApplicableAdvancedQuestions[Math.min(Math.max(0, playerAssessment.advancedStep), Math.max(0, playerAssessmentApplicableAdvancedQuestions.length - 1))]
    : undefined;
  const playerAssessmentAdvancedAnsweredCount = playerAssessmentApplicableAdvancedQuestions.filter((question) => (
    playerAssessment?.advancedAnswers[question.id] !== undefined && playerAssessment.advancedAnswers[question.id] !== null
  )).length;
  const playerAssessmentAdvancedComplete =
    playerAssessmentApplicableAdvancedQuestions.length > 0 &&
    playerAssessmentAdvancedAnsweredCount === playerAssessmentApplicableAdvancedQuestions.length;
  const playerAssessmentAdvancedResult = useMemo(() => {
    if (!playerAssessmentInitialResult || !playerAssessment) return null;
    return calculateAdvancedRatings({ initial: playerAssessmentInitialResult, answers: playerAssessment.advancedAnswers });
  }, [playerAssessment, playerAssessmentInitialResult]);
  const playerAssessmentPreviewRatings =
    playerAssessment?.kind === "advanced" && playerAssessmentAdvancedResult
      ? playerAssessmentAdvancedResult.baseRatings
      : playerAssessmentInitialResult?.profile.baseRatings;
  const playerAssessmentPreviewOverall =
    playerAssessment?.kind === "advanced" && playerAssessmentAdvancedResult
      ? playerAssessmentAdvancedResult.baseOverall
      : playerAssessmentInitialResult?.profile.baseOverall;
  const playerAssessmentPreviewFacets = playerAssessmentPreviewRatings
    ? assessmentFacetsFromRatings(playerAssessmentPreviewRatings)
    : makeFacetRatings();

  useEffect(() => {
    let cancelled = false;
    queueMicrotask(() => {
      if (!cancelled) {
        setRatingComparisons(Object.fromEntries(ATTRIBUTE_KEYS.map((facet) => [facet, "PARECIDO"])) as Record<AttributeKey, RatingComparison>);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [selectedPlayerId]);

  useEffect(() => {
    if (!supabase || !isRegisteredUser || !selectedPlayer?.globalPlayerProfileId) {
      queueMicrotask(() => setSelectedPlayerCosmetics(null));
      return;
    }
    const client = supabase;
    const profileId = selectedPlayer.globalPlayerProfileId;
    let active = true;
    const loadCosmetics = async () => {
      const result = await client.rpc("get_pachanga_public_player_card_cosmetics_v1", {
        target_player_profile_id: profileId,
      });
      if (!active || result.error) return;
      const canonical = normalizePublicPlayerCosmeticsSnapshot(result.data);
      setSelectedPlayerCosmetics(canonical?.playerProfileId === profileId ? canonical : null);
    };
    void loadCosmetics();
    const channel = client
      .channel(`public-player-cosmetics-${profileId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_player_cosmetic_public_cards", filter: `player_profile_id=eq.${profileId}` },
        () => void loadCosmetics(),
      )
      .subscribe();
    return () => {
      active = false;
      void client.removeChannel(channel);
    };
  }, [isRegisteredUser, selectedPlayer?.globalPlayerProfileId]);

  useEffect(() => {
    let cancelled = false;
    const updateEligibility = (eligibility: RatingEligibility | null | undefined, loading: boolean) => {
      queueMicrotask(() => {
        if (cancelled) return;
        if (eligibility !== undefined) setRatingEligibility(eligibility);
        setRatingEligibilityLoading(loading);
      });
    };
    if (!selectedPlayer || selectedPlayerIsOwn || selectedPlayer.inactive || selectedPlayer.goalkeeperOnly || !ratingsEnabled) {
      updateEligibility(null, false);
      return () => {
        cancelled = true;
      };
    }
    if (isDemoMode) {
      const demoWindow = ratingWindow(selectedPlayer, ratingVoterId);
      updateEligibility({
        canRate: true,
        firstRating: !demoWindow.ownVote,
        previousRatingAt: demoWindow.ownVote?.createdAt,
        requiredMatches: demoWindow.ownVote ? 3 : 0,
        sharedMatches: demoWindow.ownVote ? Math.min(3, Math.max(0, selectedPlayer.appearances - demoWindow.ownVote.matchCount)) : 0,
      }, false);
      return () => {
        cancelled = true;
      };
    }
    if (!supabase || !remoteGroupId || !isRegisteredUser) {
      updateEligibility(null, false);
      return () => {
        cancelled = true;
      };
    }

    updateEligibility(undefined, true);
    void supabase.rpc("get_pachanga_rating_eligibility", {
      target_group_id: remoteGroupId,
      target_player_id: selectedPlayer.id,
    }).then((result) => {
      if (cancelled) return;
      updateEligibility(result.error ? null : result.data as RatingEligibility, false);
      if (result.error) setSyncError(result.error.message);
    });
    return () => {
      cancelled = true;
    };
  }, [isDemoMode, isRegisteredUser, ratingEligibilityRevision, ratingVoterId, ratingsEnabled, remoteGroupId, selectedPlayer, selectedPlayerIsOwn]);

  useEffect(() => {
    if (profileFocusTarget !== "rating" || activeMobileTab !== "perfil" || !selectedPlayerId) return;

    window.setTimeout(() => {
      window.requestAnimationFrame(() => {
        playerRatingFacetGridRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
        setProfileFocusTarget(null);
      });
    }, 80);
  }, [activeMobileTab, profileFocusTarget, selectedPlayerId]);

  function editReserveLimitDraft(value: string) {
    setMatchReserveLimitDraft(value);
    if (value.trim() === "") return;
    updateMatchSettings({ ...activeMatch, reserveLimit: Math.max(0, Math.floor(Number(value) || 0)) });
  }

  function editFieldCostDraft(value: string) {
    setMatchFieldCostDraft(value);
    if (value.trim() === "") return;
    updateMatchSettings({ ...activeMatch, fieldCost: Math.max(0, Number(value) || 0) });
  }

  function commitReserveLimitDraft() {
    const nextValue = Math.max(0, Math.floor(Number(matchReserveLimitDraft) || 0));
    setEditingMatchNumberField(null);
    setMatchReserveLimitDraft(String(nextValue));
    updateMatchSettings({ ...activeMatch, reserveLimit: nextValue });
  }

  function commitFieldCostDraft() {
    const nextValue = Math.max(0, Number(matchFieldCostDraft) || 0);
    setEditingMatchNumberField(null);
    setMatchFieldCostDraft(String(nextValue));
    updateMatchSettings({ ...activeMatch, fieldCost: nextValue });
  }

  function updateMatchSettings(next: Match) {
    if (!canEditMatchSettings) return;
    updateMatch(next);
  }

  async function saveMatchConfiguration() {
    if (groupBillingLocked) {
      revealBillingPanel("La prueba gratuita ya ha cerrado 2 partidos. Activa un plan para guardar nuevos partidos.");
      return;
    }
    if (!matchCanBeSaved) return;
    const nextMatch = { ...activeMatch, configured: true, season: seasonKey(activeMatch.date) };
    const nextMatches = matches.map((match) => (match.id === activeMatch.id ? nextMatch : match));
    const nextPayload = { activeMatchId, matches: nextMatches, players, siteSettings, venues };

    setMatches(nextMatches);
    await saveRemotePayloadWithBackup(nextPayload, "partido_guardado", true);
  }

  function updatePlayer(playerId: string, next: Partial<Player>) {
    const player = players.find((item) => item.id === playerId);
    if (!player) return;
    const canEditPlayer = canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    if (!canEditPlayer) return;
    setProfileSaveMessage("");
    setPlayers((current) => current.map((item) => (item.id === playerId ? { ...item, ...next } : item)));
  }

  function startAvatarDrag(event: ReactPointerEvent<HTMLElement>, player: Player) {
    const canEditPlayer = canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    const draft = avatarDrafts[player.id];
    if (!draft?.avatar || avatarAdjustingPlayerId !== player.id || !canEditPlayer) return;

    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    avatarDragRef.current = {
      playerId: player.id,
      startX: event.clientX,
      startY: event.clientY,
      startOffsetX: clampAvatarOffset(draft.avatarOffsetX, 50),
      startOffsetY: clampAvatarOffset(draft.avatarOffsetY, 0),
    };
    setAvatarDragging(true);
    setAvatarMessage("Arrastra la foto y pulsa Guardar ficha");
  }

  function moveAvatarDrag(event: ReactPointerEvent<HTMLElement>) {
    const drag = avatarDragRef.current;
    if (!drag) return;

    event.preventDefault();
    const rect = event.currentTarget.getBoundingClientRect();
    const x = clampAvatarOffset(drag.startOffsetX - ((event.clientX - drag.startX) / Math.max(rect.width, 1)) * 100, 50);
    const y = clampAvatarOffset(drag.startOffsetY - ((event.clientY - drag.startY) / Math.max(rect.height, 1)) * 100, 0);
    setAvatarDrafts((current) => {
      const draft = current[drag.playerId];
      if (!draft) return current;
      return { ...current, [drag.playerId]: { ...draft, avatarOffsetX: x, avatarOffsetY: y } };
    });
  }

  function finishAvatarDrag(event: ReactPointerEvent<HTMLElement>) {
    if (!avatarDragRef.current) return;

    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    avatarDragRef.current = null;
    setAvatarDragging(false);
    setAvatarMessage("Encuadre listo. Pulsa Guardar ficha");
  }

  function profilePatchFor(player: Player) {
    const marketZonesGeo = normalizeMarketZonesGeo(player.marketZonesGeo);

    return {
      avatar: player.avatar,
      avatarOffsetX: player.avatar ? clampAvatarOffset(player.avatarOffsetX, 50) : undefined,
      avatarOffsetY: player.avatar ? clampAvatarOffset(player.avatarOffsetY, 0) : undefined,
      birthDate: normalizeBirthDate(player.birthDate),
      goalkeeperOnly: Boolean(player.goalkeeperOnly),
      injured: Boolean(player.injured),
      marketAvailability: player.marketAvailability ?? "",
      marketBio: player.marketBio ?? "",
      marketEnabled: Boolean(player.marketEnabled),
      marketModalities: marketModalitiesForPlayer(player),
      marketOpenToGroup: player.marketOpenToGroup ?? true,
      marketOpenToGuest: player.marketOpenToGuest ?? true,
      marketZones: marketZoneTextFromGeo(marketZonesGeo),
      marketZonesGeo,
      name: displayName(player.name) || player.name,
      outfieldPosition: rememberedOutfieldPosition(player, activeKind),
      phone: player.phone ?? "",
      position: player.position,
    };
  }

  function marketPatchFor(player: Player) {
    const marketZonesGeo = normalizeMarketZonesGeo(player.marketZonesGeo);
    const marketZoneText = marketZoneTextFromGeo(marketZonesGeo);

    return {
      active: Boolean(player.marketEnabled),
      appearances: Math.max(0, Math.floor(player.appearances || 0)),
      availabilityText: player.marketAvailability ?? "",
      avatar: player.avatar,
      avatarOffsetX: player.avatar ? clampAvatarOffset(player.avatarOffsetX, 50) : undefined,
      avatarOffsetY: player.avatar ? clampAvatarOffset(player.avatarOffsetY, 0) : undefined,
      bio: player.marketBio ?? "",
      birthDate: normalizeBirthDate(player.birthDate),
      displayName: playerDisplayName(player) || player.name,
      goalkeeperOnly: Boolean(player.goalkeeperOnly),
      goals: Math.max(0, Math.floor(player.goals || 0)),
      groupName: currentTeamName,
      media: playerMediaScore(player),
      modalities: marketModalitiesForPlayer(player),
      openToGroup: player.marketOpenToGroup ?? true,
      openToGuest: player.marketOpenToGuest ?? true,
      position: player.position,
      wins: Math.max(0, Math.floor(player.wins || 0)),
      zones: splitMarketList(marketZoneText),
      zonesGeo: marketZonesGeo,
      zonesText: marketZoneText,
    };
  }

  function publicMatchPatchFor(match: Match, active: boolean) {
    const matchVenue = venues.find((venue) => venue.id === match.venueId);
    const parsedDate = new Date(match.date);
    const day = Number.isNaN(parsedDate.getTime())
      ? ""
      : displayName(parsedDate.toLocaleDateString("es-ES", { weekday: "long" }));
    const zone = [
      matchVenue?.city,
      matchVenue?.province && matchVenue.province !== matchVenue.city ? matchVenue.province : "",
    ].filter(Boolean).join(", ") || matchVenue?.address || match.place;
    const confirmedCount = orderedGoingPlayers(match).slice(0, match.targetPlayers).length;
    const openSlots = Math.max(match.targetPlayers - confirmedCount, 0);
    const rawMinRating = publicMatchRating(match.publicMinRating, 0);
    const rawMaxRating = publicMatchRating(match.publicMaxRating, 10);
    const minRating = Math.min(rawMinRating, rawMaxRating);
    const maxRating = Math.max(rawMinRating, rawMaxRating);
    const safeSlots = active ? Math.max(1, Math.min(openSlots || match.targetPlayers, Math.floor(Number(match.publicOpenSlots) || openSlots || 1))) : 0;
    const matchLink = publicMatchUrl(match.id);

    return {
      active,
      confirmedCount,
      date: match.date,
      dateText: matchSummaryDate(match.date),
      day,
      fieldCost: Math.max(0, Number(match.fieldCost ?? 0) || 0),
      fieldName: matchVenue?.name || match.place || "Campo por confirmar",
      groupLevel: groupLevel ?? null,
      groupName: currentTeamName,
      guestsPay: match.publicGuestsPay ?? true,
      lat: matchVenue?.lat,
      lng: matchVenue?.lng,
      matchUrl: matchLink,
      maxRating,
      minRating,
      modality: match.kind ?? "futbol7",
      openSlots: safeSlots,
      placeId: matchVenue?.placeId,
      positions: normalizePublicMatchPositions(match.publicPositions),
      pricePerPlayer: match.targetPlayers > 0 ? Math.max(0, Number(match.fieldCost ?? 0) || 0) / match.targetPlayers : 0,
      requiresApproval: match.publicRequiresApproval ?? true,
      targetPlayers: Math.max(0, Math.floor(Number(match.targetPlayers) || 0)),
      title: match.title || "Partido abierto",
      zone,
    };
  }

  async function syncOpenMatchPublication(nextMatch: Match, active: boolean) {
    const nextSlots = Math.max(1, Math.min(missing || nextMatch.targetPlayers, Math.floor(Number(nextMatch.publicOpenSlots) || missing || 1)));
    const nextPublicMatch: Match = {
      ...nextMatch,
      publicMaxRating: publicMatchRating(nextMatch.publicMaxRating, 10),
      publicMinRating: publicMatchRating(nextMatch.publicMinRating, 0),
      publicOpen: active,
      publicOpenSlots: nextSlots,
      publicPositions: normalizePublicMatchPositions(nextMatch.publicPositions),
      publicRequiresApproval: nextMatch.publicRequiresApproval ?? true,
      publicGuestsPay: nextMatch.publicGuestsPay ?? true,
    };

    updateMatch(nextPublicMatch);

    if (!supabase || !remoteGroupId || !canUseAdminControls) return true;

    setSyncStatus("connecting");
    setSyncError("");
    const result = await withTimeout(
      Promise.resolve(
        supabase.rpc("sync_pachanga_open_match_authoritative_v2", {
          client_metadata: clientOperationMetadata(),
          expected_revision: remotePayloadRevisionRef.current,
          match_patch: publicMatchPatchFor(nextPublicMatch, active),
          operation_id: id(),
          target_group_id: remoteGroupId,
          target_match_id: nextPublicMatch.id,
        }),
      ),
      9000,
      "Mercado agotado",
    );

    if (result.error) {
      markRemoteWriteError(result.error.message);
      if (isRemoteRevisionConflict(result.error.message)) {
        await loadTeams(supabase, remoteGroupId).catch((error) => {
          setSyncError(error instanceof Error ? error.message : "No se pudo recargar el grupo");
        });
      }
      return false;
    }

    applyRemoteCommit(result.data as RemotePayloadCommit);
    return true;
  }

  async function loadOpenMatchRequests(client = supabase, groupId = remoteGroupId, matchId = activeMatch.id) {
    if (!client || !groupId || !matchId || !canUseAdminControls) {
      setOpenMatchRequests([]);
      return;
    }

    const result = await client
      .from("pachanga_open_match_requests")
      .select(
        "id, open_match_id, requester_user_id, requester_profile_id, requester_name, avatar, avatar_offset_x, avatar_offset_y, birth_date, position, goalkeeper_only, media, status, requested_at, player_id",
      )
      .eq("source_group_id", groupId)
      .eq("source_match_id", matchId)
      .in("status", ["pending", "accepted"])
      .order("requested_at", { ascending: true });

    if (result.error) {
      setOpenMatchRequestMessage(result.error.message);
      return;
    }

    setOpenMatchRequests(((result.data ?? []) as PublicMatchRequestRow[]).map(normalizeOpenMatchRequestRow));
  }

  async function reviewOpenMatchRequest(request: PublicMatchRequest, nextStatus: "accepted" | "rejected") {
    if (!supabase || !remoteGroupId || !canUseAdminControls) return;

    setOpenMatchRequestMessage(nextStatus === "accepted" ? "Aceptando solicitud..." : "Rechazando solicitud...");
    const result = await withTimeout(
      Promise.resolve(
        supabase.rpc("review_pachanga_open_match_request_authoritative_v2", {
          client_metadata: clientOperationMetadata(),
          expected_revision: remotePayloadRevisionRef.current,
          next_status: nextStatus,
          operation_id: id(),
          target_group_id: remoteGroupId,
          target_request_id: request.id,
        }),
      ),
      9000,
      "Solicitud agotada",
    );

    if (result.error) {
      setOpenMatchRequestMessage(result.error.message);
      markRemoteWriteError(result.error.message);
      return;
    }

    applyRemoteCommit(result.data as RemotePayloadCommit);
    await loadOpenMatchRequests(supabase, remoteGroupId, activeMatch.id);
    setOpenMatchRequestMessage(nextStatus === "accepted" ? `${request.requesterName} aceptado en el partido.` : `${request.requesterName} rechazado.`);
  }

  async function publishOpenMatch() {
    if (!matchConfigured || matchFinalized || lineupClosed || missing <= 0 || !canUseAdminControls) return;
    await syncOpenMatchPublication(
      {
        ...activeMatch,
        publicOpen: true,
        publicOpenSlots,
        publicMinRating: publicMatchRating(activeMatch.publicMinRating, 0),
        publicMaxRating: publicMatchRating(activeMatch.publicMaxRating, 10),
        publicRequiresApproval: activeMatch.publicRequiresApproval ?? true,
        publicGuestsPay: activeMatch.publicGuestsPay ?? true,
      },
      true,
    );
  }

  async function closeOpenMatch() {
    if (!activeMatch.publicOpen || !canUseAdminControls) return;
    await syncOpenMatchPublication({ ...activeMatch, publicOpen: false }, false);
  }

  async function syncOwnMarketProfile(client: NonNullable<typeof supabase>, groupId: string, player: Player) {
    const result = await withTimeout(
      Promise.resolve(
        client.rpc("sync_pachanga_market_profile_authoritative_v2", {
          client_metadata: clientOperationMetadata(),
          expected_revision: remotePayloadRevisionRef.current,
          market_intent: marketPatchFor(player),
          operation_id: id(),
          target_group_id: groupId,
          target_player_id: player.id,
        }),
      ),
      9000,
      "Mercado agotado",
    );
    if (result.error) throw new Error(result.error.message);
    applyRemoteCommit(result.data as RemotePayloadCommit);
  }

  function ownPlayerFromCommit(commit: RemotePayloadCommit, fallbackPlayerId: string) {
    const payload = normalizePayload(commit.payload);
    applyPayload(payload, commit.payload_revision);
    setSyncStatus("live");
    setSyncError("");
    return payload.players.find((player) => player.ownerUserId === currentUserId) ?? payload.players.find((player) => player.id === fallbackPlayerId);
  }

  async function saveSelectedPlayerProfile() {
    if (!selectedPlayer || !canEditSelectedPlayer) return;
    if (profileSaving) return;
    if (!playerMarketProfileComplete(selectedPlayer)) {
      setProfileSaveMessage("Para publicarte en mercado añade al menos una zona y un horario.");
      return;
    }
    const normalizedName = displayName(selectedPlayer.name) || selectedPlayer.name;
    const normalizedMarketZonesGeo = normalizeMarketZonesGeo(selectedPlayer.marketZonesGeo);
    const normalizedMarketZones = marketZoneTextFromGeo(normalizedMarketZonesGeo);
    const selectedAvatarDraft = avatarDrafts[selectedPlayer.id];
    const savedPlayerId = selectedPlayer.id;
    const nextPlayers = players.map((player) => (
      player.id === selectedPlayer.id
        ? {
            ...player,
            name: normalizedName,
            marketZones: normalizedMarketZones,
            marketZonesGeo: normalizedMarketZonesGeo,
            ...(selectedAvatarDraft ? selectedAvatarDraft : {}),
          }
        : player
    ));
    const editedPlayer = nextPlayers.find((player) => player.id === selectedPlayer.id);
    if (!editedPlayer) return;
    const nextPayload: AppPayload = { players: nextPlayers, venues, matches, activeMatchId, siteSettings };

    setProfileSaving(true);
    setProfileSaveMessage(selectedPlayerIsOwn ? "Guardando ficha universal..." : "Guardando ficha...");
    let marketWarning = "";

    try {
      if (supabase && remoteGroupId && remoteReady) {
        const client = supabase;
        const groupId = remoteGroupId;
        const result = await withTimeout(
          Promise.resolve(
            client.rpc("patch_pachanga_player_profile_authoritative_v2", {
              client_metadata: clientOperationMetadata(),
              expected_revision: remotePayloadRevisionRef.current,
              operation_id: id(),
              player_patch: profilePatchFor({ ...editedPlayer, name: normalizedName }),
              target_group_id: groupId,
              target_player_id: selectedPlayer.id,
            }),
          ),
          14000,
          "Guardado agotado",
        );
        if (result.error) {
          throw new Error(result.error.message);
        }

        applyRemoteCommit(result.data as RemotePayloadCommit);
        if (selectedPlayerIsOwn) {
          try {
            await syncOwnMarketProfile(client, groupId, { ...editedPlayer, name: normalizedName });
          } catch (marketError) {
            const message = marketError instanceof Error ? marketError.message : "No se pudo actualizar el mercado.";
            marketWarning = " Mercado pendiente.";
            markRemoteWriteError(message);
          }
          setProfileName(normalizedName);
          void withTimeout(
            Promise.resolve(
              client.rpc("update_pachanga_member_name", {
                member_name: normalizedName,
                target_group_id: groupId,
              }),
            ),
            7000,
            "Nombre de miembro agotado",
          )
            .then((memberResult) => {
              if (!memberResult.error) void loadTeamMembers(client, groupId);
            })
            .catch((error: unknown) => {
              const message = error instanceof Error ? error.message : "No se pudo actualizar el nombre de miembro.";
              markRemoteWriteError(message);
            });
        }
      } else {
        setPlayers(nextPlayers);
        if (selectedPlayerIsOwn) setProfileName(normalizedName);
        localStorage.setItem(storageKey, serializeLocalPayloadCache(nextPayload, remoteGroupId ? "server-cache" : "local-draft"));
      }

      setProfileSaveMessage(`${selectedPlayerIsOwn ? "Ficha universal guardada" : "Ficha guardada"}${marketWarning}`);
      clearAvatarDraft(savedPlayerId);
      setAvatarMessage("");
      window.setTimeout(() => setProfileSaveMessage(""), 1800);
    } catch (error) {
      const message = error instanceof Error ? error.message : "No se pudo guardar. Revisa la conexión.";
      setProfileSaveMessage(message === "Guardado agotado" ? "El guardado tarda demasiado. Revisa la conexión y prueba otra vez." : "No se pudo guardar. Revisa la conexión.");
      markRemoteWriteError(message);
      window.setTimeout(() => setProfileSaveMessage(""), 3600);
    } finally {
      setProfileSaving(false);
    }
  }

  async function addPeerRating(playerId: string) {
    const player = players.find((item) => item.id === playerId);
    if (!player) return;
    if (player.ownerUserId && player.ownerUserId === currentUserId) return;
    if (hasRealTeam && !isRegisteredUser) return;
    if (!ratingEligibility?.canRate || player.goalkeeperOnly) return;
    if (!ratingEligibility.firstRating && !window.confirm("Esta nueva valoración sustituirá a tu valoración anterior. El historial se conservará. ¿Continuar?")) return;

    const vote: RatingVote = {
      id: id(),
      voterId: ratingVoterId,
      voterName: profileName.trim() ? displayName(profileName) : undefined,
      ratingRole: ratingRoleForPlayer(player),
      matchCount: player.appearances,
      createdAt: new Date().toISOString(),
      facets: ratingFacetsForPlayer(player).reduce((next, facet) => {
        const attribute = ratingFacetAttributeMap[facet.key];
        const ownReference = ownPlayer?.ratingV2?.currentFacets?.[attribute] ?? facetAverage(ownPlayer ?? player, facet.key) * 10;
        next[facet.key] = clampRating((ownReference + RATING_COMPARISON_DELTAS[ratingComparisons[attribute]]) / 10);
        return next;
      }, {} as Record<RatingFacet, number>),
    };

    if (isDemoMode) {
      setPlayers((current) =>
        current.map((item) => (item.id === playerId ? {
          ...item,
          ratingVotes: [...(item.ratingVotes ?? []).filter((itemVote) => itemVote.voterId !== ratingVoterId), vote],
        } : item)),
      );
      setRatingEligibility((current) => current ? { ...current, canRate: false, firstRating: false, previousRatingAt: vote.createdAt, requiredMatches: 3, sharedMatches: 0 } : current);
      return;
    }
    if (!supabase || !remoteGroupId || !hasRealTeam) return;

    setSyncStatus("connecting");
    setSyncError("");

    const result = await supabase.rpc("record_pachanga_individual_rating_authoritative_v2", {
      client_metadata: clientOperationMetadata(),
      comparisons: ratingComparisons,
      expected_revision: remotePayloadRevisionRef.current,
      operation_id: crypto.randomUUID(),
      target_group_id: remoteGroupId,
      target_player_id: playerId,
    });

    if (result.error) {
      markRemoteWriteError(result.error.message);
      return;
    }

    applyRemoteCommit(result.data as RemotePayloadCommit);
    const nextEligibility = (result.data as { eligibility?: RatingEligibility }).eligibility;
    if (nextEligibility) setRatingEligibility(nextEligibility);
    setRatingEligibilityRevision((current) => current + 1);
  }

  async function uploadAvatar(file: File | undefined, playerId = selectedPlayer?.id) {
    setAvatarMessage("");
    const player = players.find((item) => item.id === playerId);
    const canEditPlayer = canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    if (!canEditPlayer) {
      setAvatarMessage("Solo tú o un admin podéis cambiar esta foto.");
      return;
    }
    if (!file || !playerId) return;

    try {
      setAvatarMessage("Recortando foto...");
      const avatar = await withTimeout(avatarDataUrl(file), 8000, "Recorte agotado");
      setAvatarDrafts((current) => ({ ...current, [playerId]: { avatar, avatarOffsetX: 50, avatarOffsetY: 0 } }));
      setAvatarAdjustingPlayerId(playerId);
      setAvatarMessage("Foto lista. Arrastra para encuadrar y pulsa Guardar ficha");
    } catch {
      setAvatarMessage("No se pudo cargar la foto.");
      window.setTimeout(() => setAvatarMessage(""), 2600);
    }
  }

  async function uploadTeamPhoto(file: File | undefined) {
    setTeamPhotoMessage("");
    if (!matchConfigured) {
      setTeamPhotoMessage("Guarda primero el partido.");
      return;
    }
    if (!canUploadTeamPhoto) {
      setTeamPhotoMessage("Entra al equipo para subir la foto.");
      return;
    }
    if (!file) return;

    try {
      setTeamPhotoMessage("Preparando foto...");
      const teamPhoto = await matchPhotoDataUrl(file);
      updateMatch({ ...activeMatch, teamPhoto });
      setTeamPhotoMessage("Foto guardada para el historial");
      window.setTimeout(() => setTeamPhotoMessage(""), 1800);
    } catch {
      setTeamPhotoMessage("No se pudo cargar la foto.");
    }
  }

  function removeTeamPhoto() {
    if (!canUseAdminControls) return;
    updateMatch({ ...activeMatch, teamPhoto: undefined });
    setTeamPhotoMessage("Foto eliminada");
    window.setTimeout(() => setTeamPhotoMessage(""), 1800);
  }

  function stopCamera() {
    cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
    cameraStreamRef.current = null;
    if (cameraVideoRef.current) cameraVideoRef.current.srcObject = null;
    setCameraPlayerId(null);
    setCameraError("");
  }

  function openCamera(playerId: string) {
    const player = players.find((item) => item.id === playerId);
    const canEditPlayer = canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    if (!canEditPlayer) {
      setAvatarMessage("Solo tú o un admin podéis cambiar esta foto.");
      return;
    }
    setCameraError("");
    setCameraPlayerId(playerId);
  }

  async function captureCameraAvatar() {
    const video = cameraVideoRef.current;
    if (!video || !cameraPlayerId || video.videoWidth === 0 || video.videoHeight === 0) {
      setCameraError("La cámara todavía no está lista.");
      return;
    }

    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext("2d");
    if (!context) {
      setCameraError("No se pudo capturar la foto.");
      return;
    }

    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    canvas.toBlob((blob) => {
      if (!blob) {
        setCameraError("No se pudo capturar la foto.");
        return;
      }
      void uploadAvatar(new File([blob], "webcam.jpg", { type: "image/jpeg" }), cameraPlayerId);
      stopCamera();
    }, "image/jpeg", 0.9);
  }

  function changeKind(kind: MatchKind) {
    if (!canEditMatchSettings) return;
    updateMatch({ ...activeMatch, kind, targetPlayers: matchKinds[kind].targetPlayers });
  }

  function selectVenue(venueId: string) {
    if (!canEditMatchSettings) return;
    const venue = venues.find((item) => item.id === venueId);
    if (!venue) return;
    const kind = venue.kind ?? activeKind;

    updateMatch({
      ...activeMatch,
      venueId,
      place: venue.name,
      fieldCost: venue.defaultCost,
      kind,
      targetPlayers: matchKinds[kind].targetPlayers,
    });
  }

  function addVenue(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canUseAdminControls) return;
    const name = newVenue.name.trim();
    if (!name) return;
    if (!selectedVenuePlace) {
      setVenuePlaceMessage(googleMapsApiKey ? "Selecciona el campo desde las sugerencias de Google Places." : "Falta configurar NEXT_PUBLIC_GOOGLE_MAPS_API_KEY.");
      return;
    }
    const kind = newVenue.kind;

    const venue: Venue = {
      address: selectedVenuePlace.address,
      city: selectedVenuePlace.city,
      country: selectedVenuePlace.country,
      id: id(),
      lat: selectedVenuePlace.lat,
      lng: selectedVenuePlace.lng,
      name: selectedVenuePlace.name || name,
      defaultCost: Number(newVenue.cost) || 0,
      kind,
      placeId: selectedVenuePlace.placeId,
      province: selectedVenuePlace.province,
    };

    setVenues((current) => [...current, venue]);
    updateMatch({
      ...activeMatch,
      venueId: venue.id,
      place: venue.name,
      fieldCost: venue.defaultCost,
      kind,
      targetPlayers: matchKinds[kind].targetPlayers,
    });
    setNewVenue({ address: "", cost: String(venue.defaultCost || 56), kind, name: "" });
    setSelectedVenuePlace(null);
    setVenuePlaceMessage("");
    setOpenQuickForm(null);
  }

  function venueUsage(venueId: string) {
    return matches.reduce(
      (usage, match) => {
        if (match.venueId !== venueId) return usage;
        if (match.closed) usage.closed += 1;
        else usage.open += 1;
        return usage;
      },
      { closed: 0, open: 0 },
    );
  }

  async function deleteVenue(venueId: string) {
    if (!canUseAdminControls) return;
    const venue = venues.find((item) => item.id === venueId);
    if (!venue) return;

    const usage = venueUsage(venueId);
    const impact = [
      usage.open ? `${usage.open} partido${usage.open === 1 ? "" : "s"} abierto${usage.open === 1 ? "" : "s"} volverán a Campo por confirmar` : "",
      usage.closed ? `${usage.closed} histórico${usage.closed === 1 ? "" : "s"} conservarán el nombre del campo` : "",
    ].filter(Boolean);

    if (!window.confirm(`¿Borrar el campo "${venue.name}"?${impact.length ? `\n\n${impact.join(". ")}.` : ""}\n\nLos partidos históricos conservarán el nombre del campo.`)) return;

    const nextVenues = venues.filter((item) => item.id !== venueId);
    const nextMatches = matches.map((match) => {
      if (match.venueId !== venueId) return match;
      if (match.closed) return { ...match, venueId: undefined };

      return {
        ...match,
        configured: false,
        fieldCost: 0,
        lineupClosed: false,
        payerId: undefined,
        place: "Campo por confirmar",
        venueId: undefined,
      };
    });
    const nextPayload: AppPayload = { activeMatchId, matches: nextMatches, players, siteSettings, venues: nextVenues };

    setVenues(nextVenues);
    setMatches(nextMatches);
    localStorage.setItem(storageKey, serializeLocalPayloadCache(nextPayload, remoteGroupId ? "server-cache" : "local-draft"));

    if (supabase && remoteGroupId && remoteReady && canManageTeam) {
      await saveRemotePayload(nextPayload);
    }
  }

  async function createTeam(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;

    const client = supabase;
    setSyncStatus("connecting");
    setSyncError("");

    try {
      const user = await getSignedUser(client);
      if (!user || isAnonymousAuthUser(user)) throw new Error("Entra con Google para crear grupos o ser admin.");
      const userId = user.id;
      const teamName = newTeamName.trim() || "Mi grupo de pachangas";
      const initialPayload = emptyTeamPayload(teamName);
      const insertResult = await client
        .from("pachanga_groups")
        .insert({ name: teamName, owner_id: userId, payload: initialPayload })
        .select("id, invite_token, name, payload, team_code, payload_revision")
        .single();

      if (insertResult.error || !insertResult.data) throw new Error(insertResult.error?.message ?? "No se pudo crear el grupo");

      const memberResult = await client.from("pachanga_group_members").insert({
        display_name: profileName.trim() || authDisplayName(user),
        group_id: insertResult.data.id,
        role: "owner",
        user_id: userId,
      });

      if (memberResult.error) throw new Error(memberResult.error.message);

      await loadTeams(client, insertResult.data.id);
      setAdminInviteToken(null);
      setOpenQuickForm(null);
    } catch (error) {
      setSyncStatus("error");
      setSyncError(error instanceof Error ? error.message : "No se pudo crear el grupo");
    }
  }

  function startPlayerAssessment(kind: PlayerAssessmentKind, seedPlayer?: Player) {
    if (!hasRealTeam || !isRegisteredUser || !currentUserId) return;
    const initial = makeAssessmentInitialInput(activeKind, seedPlayer);
    if (kind === "advanced" && seedPlayer?.assessmentSummary?.initial?.primaryPosition) {
      initial.primaryPosition = seedPlayer.assessmentSummary.initial.primaryPosition;
    }
    setPlayerAssessment({
      advancedAnswers: {},
      advancedStep: -1,
      idempotencyKey: id(),
      initial,
      initialStep: -1,
      kind,
      saving: false,
      targetPlayerId: seedPlayer?.id ?? id(),
    });
    setPlayerAssessmentMessage("");
    setOpenQuickForm(null);
    setShowImportChoices(false);
  }

  function updateAssessmentInitial(patch: Partial<InitialRatingInput>) {
    setPlayerAssessment((current) => current ? { ...current, initial: { ...current.initial, ...patch } } : current);
  }

  function toggleAssessmentMode(mode: FootballMode) {
    setPlayerAssessment((current) => {
      if (!current) return current;
      const currentModes = assessmentSelectedModes(current.initial.modeShares);
      const nextModes = currentModes.includes(mode) ? currentModes.filter((item) => item !== mode) : [...currentModes, mode];
      return { ...current, initial: { ...current.initial, modeShares: assessmentSharesFromSelectedModes(nextModes) } };
    });
  }

  function updateAssessmentInitialAnswer(questionId: InitialTechnicalQuestionId, value: AnswerValue) {
    setPlayerAssessment((current) => current ? {
      ...current,
      initial: { ...current.initial, answers: { ...current.initial.answers, [questionId]: value } },
    } : current);
  }

  function updateAssessmentAdvancedAnswer(questionId: string, value: AnswerValue) {
    setPlayerAssessment((current) => current ? { ...current, advancedAnswers: { ...current.advancedAnswers, [questionId]: value } } : current);
  }

  function setAssessmentSaving(saving: boolean) {
    setPlayerAssessment((current) => current ? { ...current, saving } : current);
  }

  function playerFromAssessmentDraft(flow: PlayerAssessmentFlow, initialResult: InitialRatingResult) {
    const existing = players.find((player) => player.id === flow.targetPlayerId);
    const position = assessmentPositionToAppPosition[flow.initial.primaryPosition];
    const name = displayName(profileName || existing?.name || authDisplayName(authUser)) || "Jugador";
    return {
      ...(existing ?? {}),
      id: flow.targetPlayerId,
      ownerUserId: currentUserId ?? undefined,
      name,
      phone: existing?.phone ?? "",
      goalkeeperOnly: Boolean(existing?.goalkeeperOnly),
      injured: Boolean(existing?.injured),
      inactive: false,
      rating: clampRating(initialResult.profile.baseOverall / 10),
      ratings: [],
      ratingVotes: [],
      position: existing?.goalkeeperOnly ? "Portero" : position,
      outfieldPosition: position,
      goals: existing?.goals ?? 0,
      assists: existing?.assists ?? 0,
      appearances: existing?.appearances ?? 0,
      wins: existing?.wins ?? 0,
      lateCancels: existing?.lateCancels ?? 0,
    } satisfies Player;
  }

  async function persistSharedEngineAssessment(args: {
    assessmentInput: Record<string, unknown>;
    kind: PlayerAssessmentKind;
    operationId: string;
    player: Player;
  }) {
    if (!supabase || !remoteGroupId) throw new Error("No hay conexión con el servidor para guardar el test.");
    const sessionResult = await supabase.auth.getSession();
    const accessToken = sessionResult.data.session?.access_token;
    if (!accessToken) throw new Error("Vuelve a entrar para guardar el test.");

    const response = await clientWriteFetch("api:ratings-assessment", "/api/ratings/assessment", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        assessmentInput: args.assessmentInput,
        clientMetadata: clientOperationMetadata(),
        expectedRevision: remotePayloadRevisionRef.current,
        groupId: remoteGroupId,
        kind: args.kind,
        operationId: args.operationId,
        playerId: args.player.id,
      }),
    });
    const payload = await response.json() as RemotePayloadCommit & { error?: string };
    if (!response.ok) throw new Error(payload.error || "No se pudo guardar el test.");
    return payload;
  }

  async function completeInitialPlayerAssessment() {
    if (!playerAssessment || playerAssessment.kind !== "initial" || !playerAssessmentInitialResult) return;
    if (!assessmentInitialIsComplete(playerAssessment.initial)) {
      setPlayerAssessmentMessage("Completa todas las respuestas del test obligatorio.");
      return;
    }
    if (!supabase || !remoteGroupId || !remoteReady || !currentUserId) {
      setPlayerAssessmentMessage("No hay conexión con el servidor para crear la ficha.");
      return;
    }

    const player = playerFromAssessmentDraft(playerAssessment, playerAssessmentInitialResult);
    setAssessmentSaving(true);
    setPlayerAssessmentMessage("Creando ficha universal...");
    try {
      const result = await withTimeout(
        persistSharedEngineAssessment({
          assessmentInput: {
            ...playerAssessment.initial,
            engineVersion: FOOTBALL_RATING_ENGINE_VERSION,
            questionnaireVersion: INITIAL_TEST_VERSION,
          },
          kind: "initial",
          operationId: playerAssessment.idempotencyKey,
          player,
        }),
        16000,
        "Test agotado",
      );
      const savedPlayer = ownPlayerFromCommit(result, player.id);
      setPlayerAssessment(null);
      setProfileName(playerDisplayName(savedPlayer ?? player));
      setPlayerProfileMode("edit");
      setProfilePane("ficha");
      setSelectedPlayerId(savedPlayer?.id ?? player.id);
      setProfileSaveMessage("Ficha creada con test inicial");
      window.setTimeout(() => setProfileSaveMessage(""), 2200);
    } catch (error) {
      setAssessmentSaving(false);
      setPlayerAssessmentMessage(error instanceof Error ? error.message : "No se pudo completar el test.");
    }
  }

  async function completeAdvancedPlayerAssessment() {
    if (!playerAssessment || playerAssessment.kind !== "advanced" || !selectedPlayer || !playerAssessmentAdvancedComplete) return;
    if (!supabase || !remoteGroupId || !remoteReady || !currentUserId) {
      setPlayerAssessmentMessage("No hay conexión con el servidor para mejorar la ficha.");
      return;
    }

    setAssessmentSaving(true);
    setPlayerAssessmentMessage("Guardando test avanzado...");
    try {
      const result = await withTimeout(
        persistSharedEngineAssessment({
          assessmentInput: {
            answers: playerAssessment.advancedAnswers,
            engineVersion: FOOTBALL_RATING_ENGINE_VERSION,
            questionnaireVersion: ADVANCED_TEST_VERSION,
          },
          kind: "advanced",
          operationId: playerAssessment.idempotencyKey,
          player: selectedPlayer,
        }),
        16000,
        "Test avanzado agotado",
      );
      const savedPlayer = ownPlayerFromCommit(result, selectedPlayer.id);
      setPlayerAssessment(null);
      setPlayerProfileMode("edit");
      setProfilePane("ficha");
      setSelectedPlayerId(savedPlayer?.id ?? selectedPlayer.id);
      setProfileSaveMessage("Ficha afinada con test avanzado");
      window.setTimeout(() => setProfileSaveMessage(""), 2200);
    } catch (error) {
      setAssessmentSaving(false);
      setPlayerAssessmentMessage(error instanceof Error ? error.message : "No se pudo completar el test avanzado.");
    }
  }

  async function openOwnPlayerProfile() {
    if (ownPlayer) {
      rememberPlayerProfileReturnTarget();
      teamGalleryReturnScrollYRef.current = null;
      setMobileAccountOpen(false);
      setPlayerProfileMode("edit");
      setProfilePane("ficha");
      setActiveMobileTab("perfil");
      setSelectedPlayerId(ownPlayer.id);
      if (selectedPlayerId === ownPlayer.id) {
        scrollToPlayerProfile();
      }
      return;
    }

    if (!hasRealTeam || !isRegisteredUser || !currentUserId) return;
    startPlayerAssessment("initial");
  }

  function ownPlayerFromImportCandidate(candidate: PlayerImportCandidate): Player | null {
    if (!currentUserId) return null;

    const source = candidate.player;
    const preferredPosition = source.goalkeeperOnly
      ? "Portero"
      : equivalentPositionForKind(source.position, activeKind);
    const outfieldPosition = source.goalkeeperOnly
      ? equivalentPositionForKind(rememberedOutfieldPosition(source, activeKind), activeKind)
      : preferredPosition;
    const importedRating = clampRating(candidate.media);

    return {
      id: id(),
      ownerUserId: currentUserId,
      name: playerDisplayName(source) || "Jugador",
      avatar: source.avatar,
      avatarOffsetX: source.avatar ? clampAvatarOffset(source.avatarOffsetX, 50) : undefined,
      avatarOffsetY: source.avatar ? clampAvatarOffset(source.avatarOffsetY, 0) : undefined,
      phone: source.phone ?? "",
      birthDate: normalizeBirthDate(source.birthDate),
      goalkeeperOnly: Boolean(source.goalkeeperOnly),
      injured: false,
      inactive: false,
      importedRating,
      importedRatingAt: new Date().toISOString(),
      importedRatingFromGroup: candidate.groupName,
      rating: importedRating,
      ratings: [],
      ratingVotes: [],
      position: preferredPosition,
      outfieldPosition: isGoalkeeperPosition(outfieldPosition) ? defaultPositionForKind(activeKind) : outfieldPosition,
      goals: 0,
      assists: 0,
      appearances: 0,
      wins: 0,
      lateCancels: 0,
    };
  }

  async function importOwnPlayerProfile(candidate: PlayerImportCandidate | undefined) {
    if (ownPlayer) {
      await openOwnPlayerProfile();
      return;
    }

    if (!candidate || !hasRealTeam || !isRegisteredUser || !currentUserId) return;

    const player = ownPlayerFromImportCandidate(candidate);
    if (!player) return;

    if (supabase && remoteGroupId && remoteReady) {
      setSyncStatus("connecting");
      setSyncError("");
      setProfileSaveMessage("Importando ficha universal...");

      const result = await supabase.rpc("upsert_pachanga_own_player_profile_authoritative_v2", {
        client_metadata: clientOperationMetadata(),
        expected_revision: remotePayloadRevisionRef.current,
        operation_id: id(),
        player_patch: profilePatchFor(player),
        target_group_id: remoteGroupId,
        target_player_id: player.id,
      });

      if (result.error) {
        setProfileSaveMessage("No se pudo importar la ficha.");
        markRemoteWriteError(result.error.message);
        window.setTimeout(() => setProfileSaveMessage(""), 2600);
        return;
      }

      const savedPlayer = ownPlayerFromCommit(result.data as RemotePayloadCommit, player.id);
      if (savedPlayer) {
        setPlayerProfileMode("edit");
        setProfilePane("ficha");
        setSelectedPlayerId(savedPlayer.id);
        setProfileName(playerDisplayName(savedPlayer));
        setSelectedImportCandidateKey(null);
        setShowImportChoices(false);
        setProfileSaveMessage("Ficha universal importada");
        window.setTimeout(() => setProfileSaveMessage(""), 1800);
      }
      return;
    }

    setPlayers((current) => [...current, player]);
    setPlayerProfileMode("edit");
    setProfilePane("ficha");
    setSelectedPlayerId(player.id);
    setProfileName(playerDisplayName(player));
    setSelectedImportCandidateKey(null);
    setShowImportChoices(false);
  }

  async function openCreatePlayerProfile() {
    if (!canUseAdminControls) {
      await openOwnPlayerProfile();
      return;
    }

    const player: Player = {
      id: id(),
      name: `Jugador ${players.length + 1}`,
      phone: "",
      goalkeeperOnly: false,
      injured: false,
      rating: 5,
      ratings: [],
      ratingVotes: [],
      position: defaultPositionForKind(activeKind),
      outfieldPosition: defaultPositionForKind(activeKind),
      goals: 0,
      assists: 0,
      appearances: 0,
      wins: 0,
      lateCancels: 0,
    };
    const nextPlayers = [...players, player];
    const nextPayload: AppPayload = { players: nextPlayers, venues, matches, activeMatchId, siteSettings };

    setProfileSaveMessage("Creando jugador...");
    if (supabase && remoteGroupId && remoteReady) {
      const saved = await saveRemotePayloadWithBackup(nextPayload, "jugador_creado", false);
      if (!saved) {
        setProfileSaveMessage("No se pudo crear el jugador.");
        window.setTimeout(() => setProfileSaveMessage(""), 2600);
        return;
      }
    } else {
      setPlayers(nextPlayers);
    }

    setPlayerProfileMode("edit");
    setProfilePane("ficha");
    setSelectedPlayerId(player.id);
    setProfileSaveMessage("Jugador creado");
    window.setTimeout(() => setProfileSaveMessage(""), 1800);
  }

  async function claimSelectedPlayer() {
    if (!selectedPlayer || selectedPlayer.ownerUserId || ownPlayer || !hasRealTeam || !isRegisteredUser || !currentUserId) return;
    startPlayerAssessment("initial", selectedPlayer);
  }

  async function deleteCurrentTeam() {
    if (!supabase || !remoteGroupId || !canManageTeam) return;
    const teamName = currentTeam?.name ?? "este grupo";
    if (!window.confirm(`¿Eliminar ${teamName}?`)) return;
    if (!window.confirm("Confirmación final: se borrarán el grupo y sus miembros.")) return;

    const client = supabase;
    setSyncStatus("connecting");
    setSyncError("");

    try {
      const backupCreated = await createTeamBackup("equipo_borrado", currentPayload(), false);
      if (!backupCreated) throw new Error("No se pudo crear una copia antes de borrar el grupo.");

      const deleteResult = await client.from("pachanga_groups").delete().eq("id", remoteGroupId);
      if (deleteResult.error) throw new Error(deleteResult.error.message);

      const nextTeam = remoteTeams.find((team) => team.id !== remoteGroupId);
      await loadTeams(client, nextTeam?.id ?? null);

      const nextParams = new URLSearchParams(window.location.search);
      if (nextTeam) {
        nextParams.set("equipo", nextTeam.teamCode);
        nextParams.set("i", compactUuid(nextTeam.inviteToken));
      } else {
        nextParams.delete("grupo");
        nextParams.delete("invite");
        nextParams.delete("equipo");
        nextParams.delete("i");
      }
      nextParams.delete("admin");
      nextParams.delete("a");
      window.history.replaceState(null, "", nextParams.toString() ? `${window.location.pathname}?${nextParams.toString()}` : window.location.pathname);
    } catch (error) {
      setSyncStatus("error");
      setSyncError(error instanceof Error ? error.message : "No se pudo eliminar el grupo");
    }
  }

  function resetTeamScopedUi() {
    setSelectedPlayerId(null);
    setTeamGalleryOpen(false);
    teamGalleryReturnScrollYRef.current = null;
    setOpenQuickForm(null);
    setCreateMenuOpen(false);
    setSelectedImportCandidateKey(null);
    setShowImportChoices(false);
    setShowSettings(false);
    setShowBillingPanel(false);
    setBillingMessage("");
    setBillingLoading(false);
    setAvatarDrafts({});
    setAvatarAdjustingPlayerId(null);
    setAdminInviteToken(null);
    setProfileSaveMessage("");
  }

  function enterPreviewDemo() {
    window.location.assign("/demo");
  }

  function selectTeam(teamId: string) {
    if (teamId === demoTeamOptionId) {
      enterPreviewDemo();
      return;
    }

    const selectedTeam = remoteTeams.find((team) => team.id === teamId);
    if (!selectedTeam) return;

    resetTeamScopedUi();
    setPreviewDemoMode(false);
    setRemoteGroupId(selectedTeam.id);
    setRemoteInviteToken(selectedTeam.inviteToken);
    setRemoteRevision(selectedTeam.payloadRevision);
    setCurrentRole(selectedTeam.role);
    setAdminInviteToken(null);
    applyPayload(selectedTeam.payload, selectedTeam.payloadRevision);
    setRemoteReady(true);
    setSyncStatus("live");
    setSyncError("");

    const nextParams = prettyTeamParams(selectedTeam);
    window.history.replaceState(null, "", `${window.location.pathname}?${nextParams.toString()}`);

    if (supabase) {
      void loadTeamMembers(supabase, selectedTeam.id).catch((error) => {
        setSyncStatus("error");
        setSyncError(error instanceof Error ? error.message : "No se pudieron cargar miembros");
      });
    }
  }

  async function updateMemberRole(member: RemoteMember, role: MemberRole) {
    if (!supabase || !remoteGroupId || !canManageRoles || member.role === "owner" || member.userId === currentUserId || role === "owner") return;

    const result = await supabase.rpc("set_pachanga_member_role", {
      next_role: role,
      operation_key: id(),
      target_group_id: remoteGroupId,
      target_user_id: member.userId,
    });

    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }

    await loadTeamMembers(supabase, remoteGroupId);
  }

  async function transferTeamOwnership(member: RemoteMember) {
    if (!supabase || !remoteGroupId || !canManageRoles || member.role === "owner" || member.userId === currentUserId || remotePayloadRevisionRef.current === null) return;
    if (!window.confirm(`¿Transferir la propiedad del grupo a ${member.displayName}? Seguirás como admin.`)) return;

    setSyncStatus("connecting");
    setSyncError("");
    const result = await supabase.rpc("transfer_pachanga_group_ownership_authoritative_v1", {
      client_metadata: clientOperationMetadata(),
      expected_revision: remotePayloadRevisionRef.current,
      operation_id: id(),
      target_group_id: remoteGroupId,
      target_user_id: member.userId,
    });
    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }
    await loadTeams(supabase, remoteGroupId);
  }

  async function removeRegisteredMember(member: RemoteMember) {
    const adminMayRemove = canManageRoles || (canManageTeam && member.role === "player");
    if (!supabase || !remoteGroupId || !adminMayRemove || member.role === "owner" || member.userId === currentUserId || remotePayloadRevisionRef.current === null) return;
    if (!window.confirm(`¿Eliminar a ${member.displayName} del grupo? Su perfil e historial se conservarán.`)) return;

    setSyncStatus("connecting");
    setSyncError("");
    const result = await supabase.rpc("remove_pachanga_group_member_authoritative_v1", {
      client_metadata: clientOperationMetadata(),
      expected_revision: remotePayloadRevisionRef.current,
      operation_id: id(),
      target_group_id: remoteGroupId,
      target_user_id: member.userId,
    });
    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }
    await loadTeams(supabase, remoteGroupId);
  }

  async function leaveCurrentTeam() {
    if (!supabase || !remoteGroupId || !hasRealTeam || remotePayloadRevisionRef.current === null) return;
    if (currentRole === "owner") {
      setSyncStatus("error");
      setSyncError("Transfiere primero la propiedad del grupo desde Configuración.");
      return;
    }
    if (!window.confirm(`¿Abandonar ${currentTeamName}? Tu ficha, Rating, logros e historial se conservarán.`)) return;

    const client = supabase;
    const leavingGroupId = remoteGroupId;
    setSyncStatus("connecting");
    setSyncError("");
    const result = await client.rpc("leave_pachanga_group_authoritative_v1", {
      client_metadata: clientOperationMetadata(),
      expected_revision: remotePayloadRevisionRef.current,
      operation_id: id(),
      target_group_id: leavingGroupId,
    });
    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }

    resetTeamScopedUi();
    const params = new URLSearchParams(window.location.search);
    ["grupo", "invite", "equipo", "i", "admin", "a", "p", "partido"].forEach((key) => params.delete(key));
    window.history.replaceState(null, "", params.toString() ? `${window.location.pathname}?${params.toString()}` : window.location.pathname);
    await loadTeams(client);
  }

  function adminInviteUrl(token: string | null = adminInviteToken) {
    if (!localHydrated || typeof window === "undefined" || !currentTeam || !token) return "";
    return `${window.location.origin}/invitacion/admin/${encodeURIComponent(compactUuid(token))}`;
  }

  async function copyTextWithFallback(text: string, fallbackTitle: string) {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch {
      // The prompt fallback below keeps copy actions usable in restricted WebViews.
    }

    if (typeof window !== "undefined") {
      window.prompt(fallbackTitle, text);
      return true;
    }

    return false;
  }

  async function createAdminInvite() {
    if (!supabase || !remoteGroupId || !canManageRoles) return;

    setSyncStatus("connecting");
    setSyncError("");

    const result = await supabase.rpc("create_pachanga_admin_invite", {
      operation_key: id(),
      target_group_id: remoteGroupId,
    });

    if (result.error || !result.data) {
      setSyncStatus("error");
      setSyncError(result.error?.message ?? "No se pudo crear la invitación de admin");
      return;
    }

    const token = String(result.data);
    setAdminInviteToken(token);
    setSyncStatus("live");
    setSyncError("");
  }

  async function copyAdminInvite() {
    let token = adminInviteToken;
    if (!token) {
      if (!supabase || !remoteGroupId || !canManageRoles) return;
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("create_pachanga_admin_invite", {
        operation_key: id(),
        target_group_id: remoteGroupId,
      });

      if (result.error || !result.data) {
        setSyncStatus("error");
        setSyncError(result.error?.message ?? "No se pudo crear la invitación de admin");
        return;
      }

      token = String(result.data);
      setAdminInviteToken(token);
    }

    const inviteUrl = adminInviteUrl(token);
    if (!inviteUrl) return;

    const copied = await copyTextWithFallback(inviteUrl, "Copia la invitación como admin (no owner)");
    if (copied) {
      setSyncStatus("live");
      setSyncError("");
      return;
    }

    setSyncStatus("error");
    setSyncError("No se pudo copiar la invitación de admin");
  }

  async function shareAdminInviteWhatsApp() {
    let token = adminInviteToken;
    if (!token) {
      if (!supabase || !remoteGroupId || !canManageRoles) return;
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("create_pachanga_admin_invite", {
        operation_key: id(),
        target_group_id: remoteGroupId,
      });

      if (result.error || !result.data) {
        setSyncStatus("error");
        setSyncError(result.error?.message ?? "No se pudo crear la invitación de admin");
        return;
      }

      token = String(result.data);
      setAdminInviteToken(token);
    }

    const inviteUrl = adminInviteUrl(token);
    const teamName = currentTeam?.name ?? "mi equipo";
    if (!inviteUrl) return;
    window.open(`https://wa.me/?text=${encodeURIComponent(`Invitación como admin (no owner) para ${teamName}\n${inviteUrl}`)}`, "_blank", "noopener,noreferrer");
  }

  async function createMatchInvitationUrl() {
    if (
      !supabase ||
      !remoteGroupId ||
      !canManageTeam ||
      !matchConfigured ||
      matchFinalized ||
      remotePayloadRevisionRef.current === null ||
      typeof window === "undefined"
    ) return "";

    setSyncStatus("connecting");
    setSyncError("");
    const result = await supabase.rpc("create_pachanga_match_link_invitation_v1", {
      client_metadata: clientOperationMetadata(),
      expected_revision: remotePayloadRevisionRef.current,
      operation_id: id(),
      target_group_id: remoteGroupId,
      target_match_id: activeMatch.id,
    });
    if (result.error || !result.data) {
      setSyncStatus("error");
      setSyncError(result.error?.message ?? "No se pudo crear la invitación al partido");
      return "";
    }

    const response = result.data as { invitation?: { token?: string } };
    const token = response.invitation?.token;
    if (!token) {
      setSyncStatus("error");
      setSyncError("El servidor no devolvió una invitación válida");
      return "";
    }

    setSyncStatus("live");
    return `${window.location.origin}/invitacion/partido/${encodeURIComponent(compactUuid(token))}`;
  }

  function publicMatchUrl(matchId = activeMatch.id) {
    if (!localHydrated || typeof window === "undefined" || !currentTeam) return "";
    return `${window.location.origin}/partido/${encodeURIComponent(currentTeam.teamCode)}/${encodeURIComponent(compactUuid(matchId))}`;
  }

  function marketScoutUrl(tab: "jugadores" | "partidos" = "jugadores") {
    if (!matchConfigured) return "/mercado";

    const params = new URLSearchParams();
    const matchLink = publicMatchUrl();
    const parsedDate = new Date(activeMatch.date);
    const day = Number.isNaN(parsedDate.getTime())
      ? ""
      : displayName(parsedDate.toLocaleDateString("es-ES", { weekday: "long" }));
    const zone = [
      activeVenue?.city,
      activeVenue?.province && activeVenue.province !== activeVenue.city ? activeVenue.province : "",
    ].filter(Boolean).join(", ") || activeVenue?.address || activeMatch.place;

    params.set("partido", activeMatch.id);
    if (remoteGroupId) params.set("grupoId", remoteGroupId);
    if (remotePayloadRevisionRef.current !== null) params.set("revision", String(remotePayloadRevisionRef.current));
    params.set("modalidad", activeKind);
    params.set("titulo", activeMatch.title || "Partido");
    params.set("fecha", matchSummaryDate(activeMatch.date));
    params.set("plazas", String(missing));
    params.set("tab", tab);
    if (day) params.set("dia", day);
    if (zone && zone !== "Campo por confirmar") params.set("zona", zone);
    if (activeVenue?.lat !== undefined && activeVenue.lng !== undefined) {
      params.set("lat", String(activeVenue.lat));
      params.set("lng", String(activeVenue.lng));
    }
    if (activeVenue?.placeId) params.set("placeId", activeVenue.placeId);
    if (matchLink) params.set("link", matchLink);

    return `/mercado?${params.toString()}`;
  }

  function currentTeamInviteUrl() {
    if (!localHydrated || typeof window === "undefined" || !currentTeam) return "";
    return `${window.location.origin}/invitacion/grupo/${encodeURIComponent(compactUuid(currentTeam.inviteToken))}`;
  }

  async function copyTeamInvite() {
    const inviteUrl = currentTeamInviteUrl();
    if (!inviteUrl) return;

    const copied = await copyTextWithFallback(inviteUrl, "Copia el enlace del equipo");
    if (copied) {
      setSyncStatus("live");
      setSyncError("");
      return;
    }

    setSyncStatus("error");
    setSyncError("No se pudo copiar el enlace");
  }

  function shareTeamInviteWhatsApp() {
    const inviteUrl = currentTeamInviteUrl();
    if (!inviteUrl) return;
    const teamName = currentTeam?.name ?? "mi equipo";
    window.open(`https://wa.me/?text=${encodeURIComponent(`Únete a ${teamName}\n${inviteUrl}`)}`, "_blank", "noopener,noreferrer");
  }

  function shareText(invitationUrl: string) {
    const date = new Date(activeMatch.date).toLocaleString("es-ES", {
      weekday: "long",
      day: "2-digit",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
    });

    return [
      "Nuevo partido",
      `${date}`,
      `${activeMatch.place}`,
      invitationUrl,
    ]
      .filter(Boolean)
      .join("\n");
  }

  function shareSharedMatchWhatsApp() {
    const sharedUrl = publicMatchUrl();
    if (!sharedUrl) return;
    window.open(`https://wa.me/?text=${encodeURIComponent(shareText(sharedUrl))}`, "_blank", "noopener,noreferrer");
  }

  async function shareMatchInvitationWhatsApp() {
    const invitationUrl = await createMatchInvitationUrl();
    if (!invitationUrl) return;
    window.open(`https://wa.me/?text=${encodeURIComponent(shareText(invitationUrl))}`, "_blank", "noopener,noreferrer");
  }

  const matchMemberShareBox = !matchFinalized && hasRealTeam ? (
    <div className="match-share-options">
      <div className="share-box">
        <span>Compartir partido</span>
        <div className="share-actions">
          <button className="copy-invite-button" type="button" onClick={() => void copySharedMatchLink()} disabled={!matchConfigured} title="Copiar enlace para miembros del grupo" aria-label="Copiar enlace del partido para miembros del grupo">
            Copiar link
          </button>
          <button className="whatsapp-icon-button" type="button" onClick={shareSharedMatchWhatsApp} disabled={!matchConfigured} title="Compartir el partido con miembros del grupo" aria-label="Compartir el partido con miembros del grupo por WhatsApp">
            <WhatsAppLogo />
          </button>
        </div>
      </div>
    </div>
  ) : null;

  const matchAdminInviteBox = !matchFinalized && hasRealTeam && canManageTeam ? (
    <div className="share-box invitation-share-box">
      <span>Invitar al partido</span>
      <div className="share-actions">
        <button className="copy-invite-button" type="button" onClick={() => void copyMatchInvitationLink()} disabled={!matchConfigured || syncStatus === "connecting"} title="Crear acceso limitado y copiar la invitación" aria-label="Crear y copiar invitación limitada al partido">
          Crear link
        </button>
        <button className="whatsapp-icon-button" type="button" onClick={() => void shareMatchInvitationWhatsApp()} disabled={!matchConfigured || syncStatus === "connecting"} title="Crear acceso limitado y enviarlo por WhatsApp" aria-label="Crear invitación limitada al partido y enviar por WhatsApp">
          <WhatsAppLogo />
        </button>
      </div>
    </div>
  ) : null;

  function handleRosterRailWheel(event: ReactWheelEvent<HTMLDivElement>) {
    const horizontalIntent = Math.abs(event.deltaX) > 0 && Math.abs(event.deltaX) >= Math.abs(event.deltaY) * 0.35;
    const shiftHorizontal = event.shiftKey && Math.abs(event.deltaY) > 0;
    if (!horizontalIntent && !shiftHorizontal) return;

    event.preventDefault();
    event.currentTarget.scrollLeft += horizontalIntent ? event.deltaX : event.deltaY;
  }

  function startRosterRailDrag(event: ReactPointerEvent<HTMLDivElement>) {
    if (event.button !== 0) return;
    if (event.target instanceof HTMLElement && event.target.closest("button,a,input,select,textarea,[role='menu']")) return;
    rosterRailDragRef.current = {
      dragged: false,
      pointerId: event.pointerId,
      scrollLeft: event.currentTarget.scrollLeft,
      startX: event.clientX,
      startY: event.clientY,
    };
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function moveRosterRailDrag(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = rosterRailDragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;

    const deltaX = event.clientX - drag.startX;
    const deltaY = event.clientY - drag.startY;
    if (!drag.dragged && Math.abs(deltaX) < 6 && Math.abs(deltaY) < 6) return;
    if (Math.abs(deltaX) < Math.abs(deltaY)) return;

    drag.dragged = true;
    suppressRosterRailClickRef.current = true;
    event.currentTarget.dataset.dragging = "true";
    event.currentTarget.scrollLeft = drag.scrollLeft - deltaX;
    event.preventDefault();
  }

  function finishRosterRailDrag(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = rosterRailDragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;

    rosterRailDragRef.current = null;
    delete event.currentTarget.dataset.dragging;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    if (drag.dragged) {
      window.setTimeout(() => {
        suppressRosterRailClickRef.current = false;
      }, 0);
    }
  }

  function cancelRosterRailClick(event: ReactMouseEvent<HTMLDivElement>) {
    if (!suppressRosterRailClickRef.current) return;
    suppressRosterRailClickRef.current = false;
    event.preventDefault();
    event.stopPropagation();
  }

  async function copySharedMatchLink() {
    const url = publicMatchUrl();
    if (!url) return;

    const copied = await copyTextWithFallback(url, "Copia el enlace del partido");
    if (!copied) {
      setSyncStatus("error");
      setSyncError("No se pudo copiar el partido");
    }
  }

  async function copyMatchInvitationLink() {
    const url = await createMatchInvitationUrl();
    if (!url) return;

    const copied = await copyTextWithFallback(url, "Copia la invitación al partido");
    if (copied) {
      setSyncStatus("live");
      setSyncError("");
      return;
    }

    setSyncStatus("error");
    setSyncError("No se pudo copiar la invitación al partido");
  }

  async function copyPlayerPhotoPrompt() {
    const copied = await copyTextWithFallback(playerPhotoPromptForChatGpt, "Copia el prompt para generar la foto");
    if (!copied) {
      setAvatarMessage("No se pudo copiar el prompt.");
      return;
    }

    setAvatarPromptCopied(true);
    window.setTimeout(() => setAvatarPromptCopied(false), 1800);
  }

  function renderTeamMiniCard(player: Player) {
    const playerFacets = ratingFacetsForPlayer(player);
    const compactAge = playerAge(player.birthDate, currentDateValue);
    const playerScore = peerAverage(player);

    return (
      <button
        aria-label={`Abrir ficha de ${playerDisplayName(player)}`}
        className={`fifa-player-card team-mini-player-card ${cardTierClass(playerScore)} ${player.inactive ? "team-mini-inactive" : ""}`}
        key={player.id}
        onClick={() => openTeamGalleryPlayerProfile(player.id)}
        type="button"
      >
        <span className="fifa-score">{overallScore(playerScore)}</span>
        {renderRatingTrendChip(player)}
        <span className="fifa-position">{positionShort(player)}</span>
        <span className="fifa-photo">
          {player.avatar ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={player.avatar} alt={`Foto de ${playerDisplayName(player)}`} draggable={false} style={avatarImageStyle(player)} />
          ) : (
            <b>+</b>
          )}
        </span>
        <strong>{playerDisplayName(player)}</strong>
        <span className="fifa-card-meta">
          {player.goals} Goles · {player.appearances} PJ{compactAge !== null ? ` · ${compactAge} años` : ""}
        </span>
        <span className="fifa-facets">
          {playerFacets.map((facet) => (
            <span key={facet.key}>
              <b>{overallScore(facetAverage(player, facet.key))}</b>
              {facet.short}
            </span>
          ))}
        </span>
        {player.inactive ? <span className="team-mini-status">Ya no está</span> : null}
      </button>
    );
  }

  function renderRankingMiniCard(row: (typeof rankedPlayers)[number], index: number) {
    const player = row.player;
    const playerFacets = ratingFacetsForPlayer(player);
    const compactAge = playerAge(player.birthDate, currentDateValue);
    const formText = row.form.hasData ? `Forma ${visibleFormPercent(row.form)}%` : "Forma pendiente";
    const mediaSource = playerRatingSource(player);

    return (
      <button
        aria-label={`Abrir ficha de ${playerDisplayName(player)} desde ranking`}
        className={`ranking-player-entry ${player.inactive ? "team-mini-inactive" : ""}`}
        key={player.id}
        onClick={() => openPlayerProfile(player.id)}
        type="button"
      >
        <span className={`fifa-player-card team-mini-player-card ranking-player-card ${cardTierClass(row.media)}`}>
          <span className="ranking-card-rank">{index + 1}</span>
          <span className="fifa-score">{overallScore(row.media)}</span>
          {renderRatingTrendChip(player)}
          <span className="fifa-position">{positionShort(player)}</span>
          <span className="fifa-photo">
            {player.avatar ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={player.avatar} alt={`Foto de ${playerDisplayName(player)}`} draggable={false} style={avatarImageStyle(player)} />
            ) : (
              <b>+</b>
            )}
          </span>
          <strong>{playerDisplayName(player)}</strong>
          <span className="fifa-facets">
            {playerFacets.map((facet) => (
              <span key={facet.key}>
                <b>{overallScore(facetAverage(player, facet.key))}</b>
                {facet.short}
              </span>
            ))}
          </span>
        </span>
        <span className="ranking-player-stats">
          <span className="ranking-card-badge">{rankingBadgeText(row)}</span>
          <span
            aria-label={`${row.goals} goles, ${row.appearances} partidos jugados, ${row.wins} partidos ganados`}
            className="ranking-stat-grid"
          >
            <span title={`${row.goals} goles`}><b>{row.goals}</b><small>G</small></span>
            <span title={`${row.appearances} partidos jugados`}><b>{row.appearances}</b><small>PJ</small></span>
            <span title={`${row.wins} partidos ganados`}><b>{row.wins}</b><small>PG</small></span>
          </span>
          <span className="ranking-card-detail">{mediaSource ? `${mediaSource} · ` : ""}{formText}{compactAge !== null ? ` · ${compactAge} años` : ""}</span>
          {player.injured || player.inactive ? (
            <span className="ranking-card-flags">
              {player.injured ? (
                <span className="inline-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                  <HospitalLogo />
                </span>
              ) : null}
              {player.inactive ? (
                <span className="inline-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                  <UserOffLogo />
                </span>
              ) : null}
            </span>
          ) : null}
        </span>
      </button>
    );
  }

  function renderPlayerCard(player: Player, team?: "A" | "B", context?: "reserve" | "waiting") {
    const matchEntry = activeMatch.players.find((entry) => entry.playerId === player.id);
    const status = player.injured || player.inactive ? "no" : matchEntry?.status;
    const isReserve = reserveIds.includes(player.id);
    const isWaiting = waitingIds.includes(player.id);
    const joinedLabel = status === "voy" ? joinedAtLabel(matchEntry?.joinedAt) : "";
    const absenceStreak = absenceStreaks.get(player.id) ?? 0;
    const showAbsenceStreak = !player.inactive && absenceStreak > 0 && status !== "voy";
    const teamClass = team === "A" ? "team-a-card" : team === "B" ? "team-b-card" : "";
    const nextTeam = team === "A" ? "B" : "A";
    const formState = playerForm(player);
    const formSummary = !player.inactive && formState.hasData ? ` · Forma ${visibleFormPercent(formState)}%` : "";
    const matchCardAge = playerAge(player.birthDate, matchFinalized ? activeMatch.date : currentDateValue);
    const playerRatingWindow = ratingWindow(player, ratingVoterId);
    const canEditThisPlayer = canEditPlayerOwnedFields({
      canUseAdminControls,
      currentUserId,
      hasRealTeam,
      isDemoMode: isDemoMode && !playerPreviewActive,
      isRegisteredUser,
      player,
    });
    const canChangeThisPlayerStatus = matchConfigured && registrationOpen && canEditThisPlayer;
    const canChangeThisPlayerPayment = paymentReady && canEditThisPlayer;
    const statusLabel = status === "voy" ? "Voy" : status === "duda" ? "Duda" : status === "no" ? "No va" : "Sin marcar";
    const paymentActionTitle = !paymentReady
      ? "Cierra la alineación para activar pagos"
      : !canEditThisPlayer
      ? "Solo este jugador o un admin pueden cambiar el pago"
      : matchEntry?.paid
      ? "Pago recibido"
      : "Marcar pago recibido";
    const paymentActionLabel = !paymentReady
      ? "Pagos pendientes hasta cerrar alineación"
      : !canEditThisPlayer
      ? "Solo este jugador o un admin pueden cambiar el pago"
      : matchEntry?.paid
      ? "Pago recibido"
      : "Marcar pago recibido";
    const ratingTitle = player.ownerUserId === currentUserId
      ? "No puedes votarte a ti mismo"
      : playerRatingWindow.canRate
      ? "Valoraciones abiertas"
      : `Valoraciones cerradas: faltan ${playerRatingWindow.waitMatches} partido${playerRatingWindow.waitMatches === 1 ? "" : "s"}`;
    const reportRevision = remotePayloadRevisionRef.current;
    const canReportConduct = Boolean(
      matchFinalized
      && hasRealTeam
      && isRegisteredUser
      && remoteGroupId
      && player.globalPlayerProfileId
      && player.ownerUserId !== currentUserId
      && reportRevision !== null
      && reportRevision > 0,
    );
    const conductReportUrl = canReportConduct
      ? `/reportar?${new URLSearchParams({
          contextId: activeMatch.id,
          contextKind: "match",
          reporterGroupId: remoteGroupId!,
          revision: String(reportRevision),
          targetGroupId: remoteGroupId!,
          targetProfileId: player.globalPlayerProfileId!,
        }).toString()}`
      : "";
    const toggleActionMenu = (event: ReactMouseEvent<HTMLButtonElement>) => {
      const triggerRect = event.currentTarget.getBoundingClientRect();
      setPlayerActionMenu((current) => {
        if (current?.playerId === player.id) return null;

        const actionCount =
          (player.inactive ? 0 : 1) +
          3 +
          (status === "voy" && !isWaiting ? 1 : 0) +
          (status === "voy" && team && canUseAdminControls ? 1 : 0) +
          (canReportConduct ? 1 : 0);
        const panelWidth = 170;
        const viewportWidth = Math.min(
          window.innerWidth,
          window.visualViewport?.width ?? window.innerWidth,
          document.documentElement.clientWidth || window.innerWidth,
        );
        const viewportHeight = Math.min(
          window.innerHeight,
          window.visualViewport?.height ?? window.innerHeight,
          document.documentElement.clientHeight || window.innerHeight,
        );
        const panelHeight = Math.min(viewportHeight - 16, actionCount * 25 + 12);
        const margin = 8;
        const preferredDownY = triggerRect.bottom + 4;
        const preferredUpY = triggerRect.top - panelHeight - 4;
        const hasRoomDown = preferredDownY + panelHeight <= viewportHeight - margin;
        const placement = hasRoomDown || triggerRect.top < viewportHeight - triggerRect.bottom ? "down" : "up";
        const y = placement === "up"
          ? Math.max(margin, preferredUpY)
          : Math.max(margin, Math.min(viewportHeight - panelHeight - margin, preferredDownY));

        return {
          maxHeight: Math.max(80, viewportHeight - margin * 2),
          playerId: player.id,
          x: Math.max(margin, Math.min(viewportWidth - panelWidth - margin, triggerRect.right - panelWidth)),
          y,
          placement,
        };
      });
    };
    const openCardProfile = (event: ReactMouseEvent<HTMLElement>) => {
      if (event.target instanceof HTMLElement && event.target.closest("button,a,input,select,textarea,[role='menu']")) return;
      openPlayerProfile(player.id);
    };

    return (
      <article className={`player-card ${status ? `status-${status}` : "status-sin"} ${teamClass} ${isReserve ? "reserve-card" : ""} ${isWaiting ? "waiting-card" : ""} ${player.inactive ? "inactive-card" : ""} ${payerId === player.id ? "payer-card" : ""} ${playerRatingWindow.canRate ? "rating-open-card" : ""} ${playerPosition(player) === "Porteria" ? "goalkeeper-card" : ""}`} key={player.id} onClick={openCardProfile}>
        <div>
          <button className="player-name" onClick={() => openPlayerProfile(player.id)}>
            {player.avatar ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={player.avatar} alt="" draggable={false} style={avatarImageStyle(player)} />
            ) : null}
            <strong>
              <span className="player-name-line">
                {playerDisplayName(player)}
                {matchCardAge !== null ? <em className="player-age-inline">{matchCardAge} años</em> : null}
              </span>
              <small>({overallScore(playerMediaScore(player))}){formSummary} · {player.goals} Goles</small>
            </strong>
          </button>
          <span className="player-meta" title={positionLabel(player)} aria-label={positionLabel(player)}>
            {positionShort(player)}
            {!player.injured && !player.inactive && formState.hasData && formState.label ? <em className={`form-chip form-${formState.status}`}>{formState.label}</em> : null}
            {isReserve && context !== "reserve" ? <em className="reserve-chip">Reserva</em> : null}
            {isWaiting && context !== "waiting" ? <em className="reserve-chip">Espera</em> : null}
            {showAbsenceStreak ? <em className="absence-chip">{absenceStreak} sin venir</em> : null}
          </span>
          {joinedLabel ? <small className="joined-at">Voy desde {joinedLabel}</small> : null}
        </div>
        <div className="card-badges">
          {!player.inactive ? (
            <button
              className={playerRatingWindow.canRate ? "rating-badge rating-open" : "rating-badge rating-closed"}
              onClick={() => openPlayerProfile(player.id, { focusRating: true })}
              title={ratingTitle}
              type="button"
              aria-label={ratingTitle}
            >
              ★
            </button>
          ) : null}
          {player.inactive ? (
            <span className="inactive-badge" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
              <UserOffLogo />
            </span>
          ) : null}
          {player.injured ? (
            <span className="injury-badge" title="Jugador lesionado" aria-label="Jugador lesionado">
              <HospitalLogo />
            </span>
          ) : null}
          {payerId === player.id ? (
            <span className="payer-badge" title="Le toca pagar el campo" aria-label="Le toca pagar el campo">
              $
            </span>
          ) : null}
        </div>
        <div className="player-actions">
          <span className={`player-status-chip player-status-${status ?? "sin"}`} aria-label={`Estado: ${statusLabel}`}>
            {statusLabel}
          </span>
          <div className="status-buttons" aria-label={`Estado de ${playerDisplayName(player)}`}>
            <button className={status === "voy" ? "selected" : ""} disabled={!canChangeThisPlayerStatus || Boolean(player.injured || player.inactive)} onClick={() => void setStatus(player.id, "voy")}>Voy</button>
            <button className={status === "duda" ? "selected" : ""} disabled={!canChangeThisPlayerStatus || Boolean(player.inactive)} onClick={() => void setStatus(player.id, "duda")}>Duda</button>
            <button className={status === "no" ? "selected danger" : ""} disabled={!canChangeThisPlayerStatus || Boolean(player.inactive)} onClick={() => void setStatus(player.id, "no")}>No</button>
          </div>
          {status === "voy" && team && canUseAdminControls ? (
            <button
              className={`team-move ${team === "A" ? "to-b" : "to-a"}`}
              disabled={lineupClosed || matchFinalized}
              onClick={() => assignPlayerTeam(player.id, nextTeam)}
              title={team === "A" ? "Mover al equipo 2" : "Mover al equipo 1"}
              aria-label={team === "A" ? "Mover al equipo 2" : "Mover al equipo 1"}
              type="button"
            >
              <span className="team-move-symbol">{team === "A" ? "→" : "←"}</span>
              <span className="team-move-label">{team === "A" ? "Equipo 2" : "Equipo 1"}</span>
            </button>
          ) : null}
          {status === "voy" && !isWaiting ? (
            <button
              className={matchEntry?.paid ? "paid-button paid" : "paid-button"}
              disabled={!canChangeThisPlayerPayment}
              onClick={() => void togglePaid(player.id)}
              title={paymentActionTitle}
              aria-label={paymentActionLabel}
            >
              $
            </button>
          ) : null}
          <button
            className="player-action-menu-trigger"
            title="Más acciones"
            aria-label={`Más acciones de ${playerDisplayName(player)}`}
            aria-expanded={playerActionMenu?.playerId === player.id}
            onClick={toggleActionMenu}
            type="button"
          >
            ⋮
          </button>
          {playerActionMenu?.playerId === player.id ? (
            <>
              <button className="player-action-menu-backdrop" type="button" aria-label="Cerrar acciones" onClick={() => setPlayerActionMenu(null)} />
              <div
                className={`player-action-menu-panel open-${playerActionMenu.placement}`}
                role="menu"
                style={{ left: playerActionMenu.x, maxHeight: playerActionMenu.maxHeight, top: playerActionMenu.y }}
              >
                {!player.inactive ? (
                  <button
                    onClick={() => {
                      setPlayerActionMenu(null);
                      openPlayerProfile(player.id, { focusRating: true });
                    }}
                    role="menuitem"
                    type="button"
                  >
                    {playerRatingWindow.canRate ? "Valorar" : "Valoraciones"}
                  </button>
                ) : null}
                <button
                  className={status === "voy" ? "selected" : ""}
                  disabled={!canChangeThisPlayerStatus || Boolean(player.injured || player.inactive)}
                  onClick={() => {
                    setPlayerActionMenu(null);
                    void setStatus(player.id, "voy");
                  }}
                  role="menuitem"
                  type="button"
                >
                  Voy
                </button>
                <button
                  className={status === "duda" ? "selected" : ""}
                  disabled={!canChangeThisPlayerStatus || Boolean(player.inactive)}
                  onClick={() => {
                    setPlayerActionMenu(null);
                    void setStatus(player.id, "duda");
                  }}
                  role="menuitem"
                  type="button"
                >
                  Duda
                </button>
                <button
                  className={status === "no" ? "selected danger" : ""}
                  disabled={!canChangeThisPlayerStatus || Boolean(player.inactive)}
                  onClick={() => {
                    setPlayerActionMenu(null);
                    void setStatus(player.id, "no");
                  }}
                  role="menuitem"
                  type="button"
                >
                  No voy
                </button>
                {status === "voy" && !isWaiting ? (
                  <button
                    className={matchEntry?.paid ? "selected paid" : ""}
                    disabled={!canChangeThisPlayerPayment}
                    onClick={() => {
                      setPlayerActionMenu(null);
                      void togglePaid(player.id);
                    }}
                    role="menuitem"
                    type="button"
                  >
                    {matchEntry?.paid ? "Pagado" : "Marcar pagado"}
                  </button>
                ) : null}
                {status === "voy" && team && canUseAdminControls ? (
                  <button
                    disabled={lineupClosed || matchFinalized}
                    onClick={() => {
                      setPlayerActionMenu(null);
                      assignPlayerTeam(player.id, nextTeam);
                    }}
                    role="menuitem"
                    type="button"
                  >
                    {team === "A" ? "Cambiar a equipo 2" : "Cambiar a equipo 1"}
                  </button>
                ) : null}
                {canReportConduct ? (
                  <button
                    onClick={() => {
                      setPlayerActionMenu(null);
                      window.location.assign(conductReportUrl);
                    }}
                    role="menuitem"
                    type="button"
                  >
                    Reportar conducta
                  </button>
                ) : null}
              </div>
            </>
          ) : null}
        </div>
      </article>
    );
  }

  const teamColorStyle = {
    "--team-a": siteSettings.teamAColor,
    "--team-b": siteSettings.teamBColor,
    "--team-a-soft": `color-mix(in srgb, ${siteSettings.teamAColor} 10%, white)`,
    "--team-b-soft": `color-mix(in srgb, ${siteSettings.teamBColor} 10%, white)`,
    "--team-a-card": `color-mix(in srgb, ${siteSettings.teamAColor} 14%, white)`,
    "--team-b-card": `color-mix(in srgb, ${siteSettings.teamBColor} 14%, white)`,
    "--team-a-muted": `color-mix(in srgb, ${siteSettings.teamAColor} 38%, white)`,
    "--team-b-muted": `color-mix(in srgb, ${siteSettings.teamBColor} 38%, white)`,
  } as CSSProperties;
  const currentTeamName = currentTeam?.name ?? displayName(siteSettings.brand) ?? "Pachangas IQ";
  const statusConfirmationPlayer = statusConfirmation ? players.find((player) => player.id === statusConfirmation.playerId) : undefined;
  const statusConfirmationPlayerName = statusConfirmationPlayer ? playerDisplayName(statusConfirmationPlayer) : "este jugador";
  const statusConfirmationTargetLabel = statusConfirmation?.nextStatus === "duda" ? "Duda" : "No voy";
  const statusConfirmationActionLabel = statusConfirmation?.nextStatus === "duda" ? "Pasar a duda" : "Confirmar baja";

  function renderPlayerAssessmentPanel() {
    if (!playerAssessment) return null;

    const isInitial = playerAssessment.kind === "initial";
    const isIntro = isInitial ? playerAssessment.initialStep === -1 : playerAssessment.advancedStep === -1;
    const currentStep = isInitial ? playerAssessment.initialStep : playerAssessment.advancedStep;
    const totalSteps = isInitial ? assessmentInitialStepCount : playerAssessmentAdvancedStepCount;
    const progressValue = isIntro ? 0 : Math.min(currentStep + 1, totalSteps);
    const previewScore = roundRating(playerAssessmentPreviewOverall ?? 50);
    const previewPosition = assessmentPositionToAppPosition[playerAssessment.initial.primaryPosition];
    const activeModes = assessmentSelectedModes(playerAssessment.initial.modeShares);
    const initialTechnicalGroup = assessmentInitialQuestionGroups[playerAssessment.initialStep - 5];
    const stepReady = isInitial
      ? assessmentInitialStepIsComplete(playerAssessment.initial, playerAssessment.initialStep)
      : playerAssessment.advancedStep === -1 || Boolean(playerAssessmentAdvancedQuestion && playerAssessment.advancedAnswers[playerAssessmentAdvancedQuestion.id] !== null && playerAssessment.advancedAnswers[playerAssessmentAdvancedQuestion.id] !== undefined);

    return (
      <section className="top-panel player-assessment-panel" aria-label={isInitial ? "Test obligatorio de ficha" : "Test avanzado de ficha"}>
        <div className="player-assessment-preview">
          <div className={`fifa-player-card readonly-card ${cardTierClass(previewScore / 10)}`}>
            <span className="fifa-score">{previewScore}</span>
            <span className="fifa-position">{positionMeta(previewPosition).short}</span>
            <span className="fifa-photo">
              <b>+</b>
            </span>
            <strong>{displayName(profileName || authDisplayName(authUser)) || "Jugador"}</strong>
            <span className="fifa-card-meta">
              {isInitial ? "Test inicial" : "Test avanzado"} · {positionMeta(previewPosition).label}
            </span>
            <div className="fifa-facets">
              {ratingFacets.map((facet) => (
                <span key={facet.key}>
                  <b>{overallScore(playerAssessmentPreviewFacets[facet.key] ?? 5)}</b>
                  {facet.short}
                </span>
              ))}
            </div>
          </div>
        </div>
        <div className="player-assessment-flow">
          <div className="player-assessment-title">
            <span>{isInitial ? "Test obligatorio" : "Test avanzado"}</span>
            <strong>{isInitial ? "Crea tu ficha inicial" : "Afina tu ficha"}</strong>
            <button type="button" onClick={() => setPlayerAssessment(null)} aria-label="Cerrar test" disabled={playerAssessment.saving}>
              ×
            </button>
          </div>
          <div className="player-assessment-progress">
            <progress max={totalSteps} value={progressValue} />
            <small>{isIntro ? "Aviso inicial" : `Paso ${progressValue}/${totalSteps}`}</small>
          </div>

          {isIntro ? (
            <div className="player-assessment-intro">
              <p>
                Este test crea tu ficha real y solo se puede completar una vez por usuario. Responde con el nivel más fiel posible: después la media subirá o bajará con partidos y valoraciones de otros jugadores.
              </p>
              <p>
                Si sales antes de terminar, no se guarda ningún resultado incompleto ni se borra tu ficha actual.
              </p>
              <button
                className="primary-button"
                type="button"
                onClick={() =>
                  setPlayerAssessment((current) => current ? {
                    ...current,
                    advancedStep: isInitial ? current.advancedStep : 0,
                    initialStep: isInitial ? 0 : current.initialStep,
                  } : current)
                }
              >
                {isInitial ? "Empezar test" : "Empezar test avanzado"}
              </button>
            </div>
          ) : null}

          {isInitial && playerAssessment.initialStep === 0 ? (
            <div className="player-assessment-step">
              <h3>¿A qué juegas normalmente?</h3>
              <div className="player-assessment-choice-grid">
                {assessmentModeOptions.map((option) => (
                  <button
                    className={activeModes.includes(option.mode) ? "selected" : ""}
                    key={option.mode}
                    type="button"
                    aria-pressed={activeModes.includes(option.mode)}
                    onClick={() => toggleAssessmentMode(option.mode)}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {isInitial && playerAssessment.initialStep === 1 ? (
            <div className="player-assessment-step">
              <h3>Posición en el campo</h3>
              <div className="player-assessment-choice-grid">
                {Object.entries(POSITION_LABELS).map(([position, label]) => (
                  <button
                    className={playerAssessment.initial.primaryPosition === position ? "selected" : ""}
                    key={position}
                    type="button"
                    onClick={() => updateAssessmentInitial({ primaryPosition: position as AssessmentPosition, secondaryPositions: [] })}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {isInitial && playerAssessment.initialStep === 2 ? (
            <div className="player-assessment-step">
              <h3>¿Cuál es o ha sido tu nivel más alto?</h3>
              <div className="player-assessment-choice-grid">
                {assessmentExperienceOptions.map((option) => (
                  <button
                    className={playerAssessment.initial.experienceLevel === option.id ? "selected" : ""}
                    key={option.id}
                    type="button"
                    onClick={() => updateAssessmentInitial({ experienceLevel: option.id })}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {isInitial && playerAssessment.initialStep === 3 ? (
            <div className="player-assessment-step">
              <h3>¿Cuándo jugabas a ese nivel?</h3>
              <div className="player-assessment-choice-grid compact">
                {assessmentYearsSinceLevelOptions.map((option) => (
                  <button
                    className={playerAssessment.initial.yearsSinceLevel === option.value ? "selected" : ""}
                    key={option.value}
                    type="button"
                    onClick={() => updateAssessmentInitial({ yearsSinceLevel: option.value })}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {isInitial && playerAssessment.initialStep === 4 ? (
            <div className="player-assessment-step">
              <h3>¿Con qué frecuencia juegas o entrenas?</h3>
              <div className="player-assessment-choice-grid">
                {Object.entries(FREQUENCIES).map(([frequencyId, frequency]) => (
                  <button
                    className={playerAssessment.initial.frequency === frequencyId ? "selected" : ""}
                    key={frequencyId}
                    type="button"
                    onClick={() => updateAssessmentInitial({ frequency: frequencyId as FrequencyId })}
                  >
                    {frequency.label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {isInitial && initialTechnicalGroup ? (
            <div className="player-assessment-step">
              <span>{initialTechnicalGroup.subtitle}</span>
              <h3>{initialTechnicalGroup.title}</h3>
              {initialTechnicalGroup.questionIds.map((questionId) => {
                const question = INITIAL_TECHNICAL_QUESTIONS.find((item) => item.id === questionId);
                if (!question) return null;
                return (
                  <div className="player-assessment-question" key={question.id}>
                    <p>{question.prompt}</p>
                    <div className="player-assessment-choice-grid">
                      {assessmentInitialAnswerOptions[question.id].map((option) => (
                        <button
                          className={playerAssessment.initial.answers[question.id] === option.value ? "selected" : ""}
                          key={option.value}
                          type="button"
                          onClick={() => updateAssessmentInitialAnswer(question.id, option.value)}
                        >
                          {option.label}
                        </button>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          ) : null}

          {!isInitial && !isIntro ? (
            <div className="player-assessment-step">
              {playerAssessmentAdvancedQuestion ? (
                <div className="player-assessment-question">
                  <span>{playerAssessmentAdvancedQuestion.id}</span>
                  <h3>{playerAssessmentAdvancedQuestion.prompt}</h3>
                  <div className="player-assessment-choice-grid">
                    {assessmentAdvancedAnswerOptions(playerAssessmentAdvancedQuestion).map((option) => (
                      <button
                        className={playerAssessment.advancedAnswers[playerAssessmentAdvancedQuestion.id] === option.value ? "selected" : ""}
                        key={option.value}
                        type="button"
                        onClick={() => updateAssessmentAdvancedAnswer(playerAssessmentAdvancedQuestion.id, option.value)}
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                </div>
              ) : (
                <p className="player-assessment-empty">No hay preguntas avanzadas disponibles para esta ficha.</p>
              )}
            </div>
          ) : null}

          {!isIntro ? (
            <div className="player-assessment-actions">
              <button
                className="ghost-form-button"
                type="button"
                disabled={playerAssessment.saving || currentStep <= 0}
                onClick={() =>
                  setPlayerAssessment((current) => current ? {
                    ...current,
                    advancedStep: isInitial ? current.advancedStep : Math.max(0, current.advancedStep - 1),
                    initialStep: isInitial ? Math.max(0, current.initialStep - 1) : current.initialStep,
                  } : current)
                }
              >
                Atrás
              </button>
              <button
                className="primary-button"
                type="button"
                disabled={playerAssessment.saving || !stepReady}
                onClick={() => {
                  if (isInitial) {
                    if (playerAssessment.initialStep >= assessmentInitialStepCount - 1) {
                      void completeInitialPlayerAssessment();
                    } else {
                      setPlayerAssessment((current) => current ? { ...current, initialStep: current.initialStep + 1 } : current);
                    }
                    return;
                  }
                  if (playerAssessment.advancedStep >= playerAssessmentAdvancedStepCount - 1) {
                    void completeAdvancedPlayerAssessment();
                  } else {
                    setPlayerAssessment((current) => current ? { ...current, advancedStep: current.advancedStep + 1 } : current);
                  }
                }}
              >
                {playerAssessment.saving
                  ? "Guardando..."
                  : isInitial && playerAssessment.initialStep >= assessmentInitialStepCount - 1
                    ? "Crear ficha"
                    : !isInitial && playerAssessment.advancedStep >= playerAssessmentAdvancedStepCount - 1
                      ? "Guardar test avanzado"
                      : "Continuar"}
              </button>
            </div>
          ) : null}
          {playerAssessmentMessage ? <small className="player-assessment-message">{playerAssessmentMessage}</small> : null}
        </div>
      </section>
    );
  }

  function renderSelectedPlayerCard(editable: boolean) {
    if (!selectedPlayer) return null;
    const cardCanEdit = Boolean(editable && canEditSelectedPlayer);
    const cardCanAdjustAvatar = Boolean(editable && canAdjustSelectedAvatar);

    return (
      <div className="fifa-card-shell">
        <PlayerCosmeticCard
          className={`${cardCanEdit ? "" : "readonly-card"} ${cardTierClass(selectedPeerScore)} ${avatarDragging && cardCanAdjustAvatar ? "avatar-dragging" : ""}`}
          cosmetics={selectedPlayerCosmetics?.enabled ? selectedPlayerCosmetics.equipped : undefined}
          facets={selectedRatingFacets.map((facet) => ({
            key: facet.key,
            label: facet.short,
            value: overallScore(facetAverage(selectedPlayer, facet.key)),
          }))}
          meta={`${selectedPlayer.goals} Goles · ${selectedPlayer.appearances} PJ${selectedPlayerAge !== null ? ` · ${selectedPlayerAge} años` : ""}`}
          name={playerDisplayName(selectedPlayer)}
          featuredAchievement={selectedPlayerCosmetics?.enabled ? selectedPlayerCosmetics.featuredBadge : null}
          loadout={selectedPlayerCosmetics?.enabled ? selectedPlayerCosmetics.loadout : null}
          photoAction={cardCanEdit ? (
            <label className="fifa-photo-action" title={selectedAvatarPreview ? "Cambiar foto" : "Añadir foto"}>
              {selectedAvatarPreview ? "Cambiar foto" : "Añadir foto"}
              <input
                type="file"
                accept="image/*"
                aria-label={selectedAvatarPreview ? "Cambiar foto del jugador" : "Añadir foto del jugador"}
                onClick={(event) => {
                  event.currentTarget.value = "";
                }}
                onChange={(event) => {
                  void uploadAvatar(event.currentTarget.files?.[0], selectedPlayer.id);
                  event.currentTarget.value = "";
                }}
              />
            </label>
          ) : undefined}
          photoAlt={`Foto de ${playerDisplayName(selectedPlayer)}`}
          photoClassName={cardCanAdjustAvatar ? "draggable-avatar" : ""}
          photoProps={{
            onPointerCancel: cardCanAdjustAvatar ? finishAvatarDrag : undefined,
            onPointerDown: cardCanAdjustAvatar ? (event) => startAvatarDrag(event, selectedPlayer) : undefined,
            onPointerMove: cardCanAdjustAvatar ? moveAvatarDrag : undefined,
            onPointerUp: cardCanAdjustAvatar ? finishAvatarDrag : undefined,
          }}
          photoSrc={selectedAvatarPreview}
          photoStyle={avatarImageStyle(selectedAvatarDraft ?? selectedPlayer)}
          position={positionShort(selectedPlayer)}
          score={overallScore(selectedPeerScore)}
          trend={renderRatingTrendChip(selectedPlayer)}
        />
        {cardCanAdjustAvatar ? (
          <small className="avatar-adjust-hint">Arrastra la foto dentro de la carta. El encuadre se guarda al pulsar Guardar ficha.</small>
        ) : null}
        {editable ? (
          <>
            <div className="avatar-actions">
              <label className="avatar-action-button">
                Foto
                <input
                  type="file"
                  accept="image/*"
                  disabled={!canEditSelectedPlayer}
                  onChange={(event) => {
                    void uploadAvatar(event.currentTarget.files?.[0], selectedPlayer.id);
                    event.currentTarget.value = "";
                  }}
                />
              </label>
              <label className="avatar-action-button">
                Cámara
                <input
                  type="file"
                  accept="image/*"
                  capture="user"
                  disabled={!canEditSelectedPlayer}
                  onChange={(event) => {
                    void uploadAvatar(event.currentTarget.files?.[0], selectedPlayer.id);
                    event.currentTarget.value = "";
                  }}
                />
              </label>
              <button className="avatar-action-button" type="button" onClick={() => openCamera(selectedPlayer.id)} disabled={!canEditSelectedPlayer}>
                Webcam
              </button>
            </div>
            {canEditSelectedPlayer ? (
              <div className="avatar-prompt-help">
                <span className="avatar-prompt-info" aria-hidden="true">i</span>
                <small>Prompt para ChatGPT: crea un retrato PNG transparente con estilo de carta.</small>
                <button className="avatar-prompt-copy" type="button" onClick={() => void copyPlayerPhotoPrompt()}>
                  {avatarPromptCopied ? "Copiado" : "Copiar prompt"}
                </button>
              </div>
            ) : null}
            {avatarMessage ? <small className="avatar-message">{avatarMessage}</small> : null}
            {cameraPlayerId === selectedPlayer.id ? (
              <div className="camera-panel">
                <video ref={cameraVideoRef} autoPlay muted playsInline />
                <div>
                  <button type="button" onClick={captureCameraAvatar}>Usar foto</button>
                  <button type="button" onClick={stopCamera}>Cerrar</button>
                </div>
                {cameraError ? <small>{cameraError}</small> : null}
              </div>
            ) : null}
          </>
        ) : null}
      </div>
    );
  }

  function renderSelectedPlayerRatingPanel() {
    if (!selectedPlayer) return null;
    const socialDisclosure = socialRatingDisclosure(selectedPlayer.ratingV2?.evaluatorCount ?? 0);

    return (
      <div className={canRateSelectedPlayer ? "rating-box rating-open-box" : "rating-box rating-locked-box"}>
        <div className="rating-box-title">
          <span>Media y valoraciones</span>
          <em className={canRateSelectedPlayer ? "rating-state open" : "rating-state closed"}>
            {canRateSelectedPlayer ? "Abiertas" : "Cerradas"}
          </em>
        </div>
        <div className="rating-summary-grid">
          <div className="rating-summary-card rating-summary-main">
            <span>Actual</span>
            <strong>{Math.round(selectedPlayer.ratingV2?.currentOverall ?? selectedPeerScore * 10)}</strong>
            <small>La cifra principal de la carta</small>
          </div>
          <div className="rating-summary-card">
            <span>Base</span>
            <strong>{Math.round(selectedPlayer.ratingV2?.baseOverall ?? selectedPlayer.rating * 10)}</strong>
            <small>Tests del jugador</small>
          </div>
          <div className="rating-summary-card">
            <span>Calibrada</span>
            {socialDisclosure.canShowAggregate ? (
              <>
                <strong>{Math.round(selectedPlayer.ratingV2?.calibratedOverall ?? selectedPeerScore * 10)}</strong>
                <small>{socialDisclosure.evaluatorCount} evaluadores · fiabilidad {Math.round(selectedPlayer.ratingV2?.reliability ?? 0)}%</small>
              </>
            ) : (
              <>
                <strong>{socialDisclosure.evaluatorCount}/{socialDisclosure.requiredEvaluators}</strong>
                <small>Calibración en curso. Faltan {socialDisclosure.remaining} evaluador{socialDisclosure.remaining === 1 ? "" : "es"} independiente{socialDisclosure.remaining === 1 ? "" : "s"}.</small>
              </>
            )}
          </div>
          {selectedForm ? (
            <div className={`form-state-card ${canRateSelectedPlayer ? "rating-summary-wide" : ""} ${selectedForm.hasData ? `form-${selectedForm.status}` : "form-pending"}`}>
              {selectedForm.hasData ? (
                <>
                  <b>Forma actual {visibleFormPercent(selectedForm)}%</b>
                  <em>{selectedForm.label}</em>
                  <small>Valor para equilibrar: {overallScore(selectedEffectiveScore)}</small>
                  <small>Fiabilidad: {selectedForm.reliability}%</small>
                  {selectedForm.notes.length ? <small>{selectedForm.notes.join(" · ")}</small> : null}
                </>
              ) : (
                <>
                  <b>Forma pendiente</b>
                  <em>Sin partidos finalizados</em>
                  <small>Para equilibrar cuenta como neutral hasta tener datos reales.</small>
                </>
              )}
            </div>
          ) : null}
        </div>
        <p className="rating-help">{selectedRatingStatusText}</p>
        {ratingEligibility && !ratingEligibility.firstRating ? (
          <div className="rating-eligibility-progress" aria-label={`Partidos compartidos: ${ratingSharedMatches} de 3`}>
            <span>Partidos compartidos desde tu valoración</span>
            <strong>{ratingSharedMatches}/3</strong>
            <progress max={3} value={ratingSharedMatches} />
            {ratingEligibility.previousRatingAt ? <small>Valoración anterior: {new Date(ratingEligibility.previousRatingAt).toLocaleDateString("es-ES")}</small> : null}
          </div>
        ) : null}
        {selectedPlayerIsOwn && assessmentSummaryKindCompleted(selectedPlayer, "initial") ? (
          <div className="assessment-followup">
            {assessmentSummaryKindCompleted(selectedPlayer, "advanced") ? (
              <small>Test avanzado completado. La ficha seguirá evolucionando con valoraciones de compañeros.</small>
            ) : (
              <button type="button" onClick={() => startPlayerAssessment("advanced", selectedPlayer)}>
                Mejorar precisión de mi ficha
              </button>
            )}
          </div>
        ) : null}
        {!selectedPlayer.goalkeeperOnly && !selectedPlayerIsOwn ? (
          <div className="relative-rating-form" ref={playerRatingFacetGridRef}>
            <strong>Compáralo contigo en cada aspecto.</strong>
            <div className="relative-rating-facets">
              {ATTRIBUTE_KEYS.map((facet) => (
                <fieldset key={facet} disabled={!canRateSelectedPlayer}>
                  <legend>{OUTFIELD_FACET_LABELS[facet]}</legend>
                  <div className="relative-rating-options">
                    {RATING_COMPARISON_OPTIONS.map((option) => (
                      <button
                        aria-pressed={ratingComparisons[facet] === option.id}
                        className={ratingComparisons[facet] === option.id ? "selected" : ""}
                        key={option.id}
                        onClick={() => setRatingComparisons((current) => ({ ...current, [facet]: option.id }))}
                        type="button"
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                </fieldset>
              ))}
            </div>
            <button type="button" onClick={() => void addPeerRating(selectedPlayer.id)} disabled={!canRateSelectedPlayer}>
              {selectedRatingButtonText}
            </button>
          </div>
        ) : null}
        <div className="rating-evolution">
          <span>Evolución</span>
          {selectedRatingChartHistory.length > 0 ? (
            <div className="rating-line-chart">
              <div className="rating-chart-legend">
                {selectedRatingFacets.map((facet) => (
                  <em key={facet.key}>
                    <i style={{ background: ratingFacetColors[facet.key] }} />
                    {facet.short}
                  </em>
                ))}
              </div>
              <svg
                role="img"
                aria-label="Evolución temporal de las valoraciones por habilidad"
                viewBox={`0 0 ${ratingChart.width} ${ratingChart.height}`}
              >
                <line x1={ratingChart.left} x2={ratingChart.width - ratingChart.right} y1={ratingChartY(10)} y2={ratingChartY(10)} />
                <line x1={ratingChart.left} x2={ratingChart.width - ratingChart.right} y1={ratingChartY(5)} y2={ratingChartY(5)} />
                <line x1={ratingChart.left} x2={ratingChart.width - ratingChart.right} y1={ratingChartY(1)} y2={ratingChartY(1)} />
                {[10, 5, 1].map((value) => (
                  <text className="rating-chart-y-label" key={value} x="4" y={ratingChartY(value) + 4}>
                    {ratingPoints(value)}
                  </text>
                ))}
                {selectedRatingChartHistory.map((vote, index) => {
                  const x = ratingChartX(index, selectedRatingChartHistory.length);
                  return (
                    <g className="rating-chart-tick" key={vote.id}>
                      <line x1={x} x2={x} y1={ratingChart.top} y2={ratingChart.bottom} />
                      <text x={x} y={ratingChart.height - 16}>P{vote.matchCount}</text>
                      <text x={x} y={ratingChart.height - 3}>{ratingVoteDateLabel(vote.createdAt)}</text>
                    </g>
                  );
                })}
                {selectedRatingFacets.map((facet, facetIndex) => (
                  <g key={facet.key}>
                    <path
                      d={ratingLinePath(selectedRatingChartHistory, facet.key, facetIndex, selectedRatingFacets.length)}
                      stroke={ratingFacetColors[facet.key]}
                    />
                    {selectedRatingChartHistory.map((vote, index) => {
                      const value = clampRating(vote.facets[facet.key] ?? 5);
                      return (
                        <circle
                          cx={ratingChartX(index, selectedRatingChartHistory.length, facetIndex, selectedRatingFacets.length)}
                          cy={ratingChartY(value)}
                          fill={ratingFacetColors[facet.key]}
                          key={`${vote.id}-${facet.key}`}
                          r="3"
                        >
                          <title>
                            {facet.label}: {overallScore(value)} · Partido {vote.matchCount} · {ratingVoteDateLabel(vote.createdAt)}
                          </title>
                        </circle>
                      );
                    })}
                  </g>
                ))}
              </svg>
            </div>
          ) : (
            <small>Sin evolución todavía</small>
          )}
        </div>
      </div>
    );
  }

  return (
    <main className="min-h-screen bg-[#f7f6f0] text-[#1d2521]" data-mobile-tab={activeMobileTab} style={teamColorStyle}>
      <section className={isDemoMode ? "hero demo-hero" : "hero team-hero"} id="inicio">
        <div>
          {isDemoMode ? (
            <>
              <div className="brand-lockup" aria-label={siteSettings.brand}>
                <img className="brand-hero-logo" src="/brand/pachangas-logo-hero.png" alt={siteSettings.brand} />
              </div>
              <h1>{siteSettings.title}</h1>
            </>
          ) : (
            <div className="team-brand-block" aria-label={`Equipo ${currentTeamName}`}>
              <img className="team-hero-logo" src="/brand/pachangas-logo-hero.png" alt="Pachangas IQ" />
              <span>Equipo: {currentTeamName}</span>
            </div>
          )}
          <p className="hero-copy">{siteSettings.subtitle}</p>
        </div>
        <div className="hero-action-stack">
          {isRegisteredUser || !needsLoginForSharedLink ? (
            <div className="hero-account-row">
              {isRegisteredUser ? (
                <GoogleSignInButton className="google-signout-button" label="Cerrar sesión" onClick={() => void signOut()} />
              ) : (
                <GoogleSignInButton label={googleButtonText} onClick={() => void signInWithGoogle()} disabled={!supabase || !googleClientId} />
              )}
            </div>
          ) : null}
          <div className="hero-actions">
            {canPreviewPlayerView ? (
              <AdminViewPreviewButton
                active={playerPreviewActive}
                className="admin-view-preview-desktop secondary-button"
                onToggle={toggleAdminPlayerView}
              />
            ) : null}
            <a className="manual-link-button" href="/manual" title="Manual de usuario" aria-label="Abrir manual de usuario">
              <svg aria-hidden="true" viewBox="0 0 24 24">
                <path d="M6 3h10.5A2.5 2.5 0 0 1 19 5.5V21l-3-1.8L13 21l-3-1.8L7 21l-3-1.8V5A2 2 0 0 1 6 3Zm0 2v12.6l1 .6 3-1.8 3 1.8 3-1.8 1 .6V5.5a.5.5 0 0 0-.5-.5H6Zm2 3h7v2H8V8Zm0 4h7v2H8v-2Z" />
              </svg>
            </a>
            <button
              className="secondary-button personal-action-button"
              type="button"
              onClick={() => void openOwnPlayerProfile()}
              disabled={!hasRealTeam || !isRegisteredUser || needsLoginForSharedLink}
            >
              Mi ficha
            </button>
            <button className="secondary-button" type="button" onClick={openTeamGallery} disabled={needsLoginForSharedLink}>
              Mi equipo
            </button>
            {hasRealTeam && isRegisteredUser ? (
              <a className="secondary-button" href={`/equipo/identidad${remoteGroupId ? `?grupo=${remoteGroupId}` : ""}`}>
                Identidad
              </a>
            ) : null}
            <a className="secondary-button market-link-button" href="/mercado">
              Mercado
            </a>
            <div className="create-menu desktop-create-menu" ref={createMenuRef}>
              <button
                className="primary-button create-menu-button"
                type="button"
                aria-expanded={createMenuOpen}
                aria-haspopup="menu"
                onClick={() => setCreateMenuOpen((open) => !open)}
              >
                Crear <span aria-hidden="true">⌄</span>
              </button>
              {createMenuOpen ? (
                <div className="create-menu-panel" role="menu">
                  <button type="button" role="menuitem" onClick={() => runCreateAction(createMatch)} disabled={!canUseAdminControls}>
                    Partido
                  </button>
                  <button type="button" role="menuitem" onClick={() => runCreateAction(() => void openCreatePlayerProfile())} disabled={!canUseAdminControls && (!hasRealTeam || !isRegisteredUser)}>
                    Ficha jugador
                  </button>
                  <button type="button" role="menuitem" onClick={() => runCreateAction(() => showQuickForm("venue"))} disabled={!canUseAdminControls}>
                    Campo
                  </button>
                  <button type="button" role="menuitem" onClick={() => runCreateAction(() => showQuickForm("team"))}>
                    Grupo de pachangas
                  </button>
                </div>
              ) : null}
            </div>
            {canUseAdminControls ? (
              <button className="secondary-button" onClick={toggleSettingsPanel}>
                Configurar
              </button>
            ) : null}
          </div>
        </div>
      </section>

      {openQuickForm === "venue" ? (
        <form className="top-panel quick-create-form top-venue-form" ref={venueFormRef} onSubmit={addVenue}>
          <input
            ref={venueNameInputRef}
            placeholder="Crear campo: nombre"
            value={newVenue.name}
            onChange={(event) => {
              setNewVenue({ ...newVenue, address: "", name: event.target.value });
              setSelectedVenuePlace(null);
              setVenuePlaceMessage("");
            }}
          />
          <label className="money-input">
            <input
              type="number"
              min="0"
              placeholder="Precio"
              value={newVenue.cost}
              onChange={(event) => setNewVenue({ ...newVenue, cost: event.target.value })}
            />
            <span>€</span>
          </label>
          <select value={newVenue.kind} onChange={(event) => setNewVenue({ ...newVenue, kind: event.target.value as MatchKind })}>
            {Object.entries(matchKinds).map(([kind, config]) => (
              <option key={kind} value={kind}>{config.label}</option>
            ))}
          </select>
          <button type="submit" disabled={!selectedVenuePlace}>Guardar campo</button>
          <div className={selectedVenuePlace ? "venue-place-status selected" : `venue-place-status ${venuePlaceStatus}`}>
            {selectedVenuePlace ? (
              <>
                <strong>Dirección verificada</strong>
                <span>{selectedVenuePlace.address}</span>
              </>
            ) : venuePlaceStatus === "missing-key" ? (
              <>
                <strong>Google Places pendiente</strong>
                <span>Configura NEXT_PUBLIC_GOOGLE_MAPS_API_KEY para crear campos reales.</span>
              </>
            ) : venuePlaceStatus === "loading" ? (
              <span>Cargando Google Places...</span>
            ) : (
              <span>Escribe y elige una sugerencia de Google Places.</span>
            )}
            {venuePlaceMessage ? <small>{venuePlaceMessage}</small> : null}
          </div>
        </form>
      ) : null}

      {openQuickForm === "team" ? (
        <form className="top-panel quick-create-form team-create-form top-team-form" ref={teamFormRef} onSubmit={createTeam}>
          <input value={newTeamName} onChange={(event) => setNewTeamName(event.target.value)} placeholder="Nombre del grupo de pachangas" />
          <button type="submit" disabled={!canCreateTeam}>Crear grupo</button>
          {!canCreateTeam ? (
            <GoogleSignInButton label="Continuar con Google" onClick={() => void signInWithGoogle()} disabled={!supabase || !googleClientId} />
          ) : null}
          <button className="ghost-form-button" type="button" onClick={() => setOpenQuickForm(null)}>Cerrar</button>
        </form>
      ) : null}

      {showGroupAccessPanel ? (
        <section className="top-panel team-access-panel" ref={teamAccessPanelRef}>
          <div className="team-access-current">
            <span>Grupo de Pachangas</span>
            {remoteTeams.length > 0 || previewDemoMode || isRegisteredUser ? (
              <select value={previewDemoMode ? demoTeamOptionId : remoteGroupId ?? ""} onChange={(event) => selectTeam(event.target.value)}>
                <option value="" disabled>Elige grupo o demo</option>
                <option value={demoTeamOptionId}>Mundo Demo</option>
                {remoteTeams.map((team) => (
                  <option key={team.id} value={team.id}>{groupOptionLabel(team)}</option>
                ))}
              </select>
            ) : (
              <strong>Sin grupo todavía</strong>
            )}
          </div>
          <div className="team-access-meta">
            <span>ID grupo</span>
            <strong>{previewDemoMode ? "DEMO" : currentTeam?.teamCode ?? "-"}</strong>
          </div>
          <div className="team-access-meta team-access-role">
            <span>Rol</span>
            <strong>{previewDemoMode ? (playerPreviewActive ? "Jugador (vista)" : "Demo") : memberRoleLabel(displayedRole)}</strong>
          </div>
          <div className="team-access-meta team-access-level">
            <span>Nivel del equipo</span>
            <strong>{groupLevel === null ? "-" : overallScore(groupLevel)}</strong>
            {groupLevel !== null ? <small>{activeRosterCount} jugador{activeRosterCount === 1 ? "" : "es"} activos</small> : null}
          </div>
          {showTeamAdminPanel ? (
            <>
              <div className="team-invite-link">
                <span>Invitar al grupo</span>
                <div className="team-invite-actions">
                  <button className="copy-icon-button" type="button" onClick={() => void copyTeamInvite()} disabled={!currentTeamInviteUrl()} title="Copiar invitación" aria-label="Copiar invitación">
                    <CopyLogo />
                  </button>
                  <button className="whatsapp-icon-button" type="button" onClick={shareTeamInviteWhatsApp} disabled={!currentTeamInviteUrl()} title="Enviar por WhatsApp" aria-label="Enviar por WhatsApp">
                    <WhatsAppLogo />
                  </button>
                </div>
              </div>
              <button
                className="trash-icon-button team-delete-button"
                disabled={!remoteGroupId || !canManageTeam}
                onClick={() => void deleteCurrentTeam()}
                title="Eliminar grupo"
                type="button"
                aria-label="Eliminar grupo"
              >
                <TrashLogo />
              </button>
            </>
          ) : null}
          <small className={`sync-status sync-${syncStatus}`}>
            {previewDemoMode ? "Demo local: no modifica tu grupo real" : syncStatus === "live" ? "Grupo privado sincronizado" : syncStatus === "connecting" ? "Conectando..." : syncStatus === "error" ? `Sin sync: ${syncError}` : "Crea un grupo o entra con invitación"}
          </small>
        </section>
      ) : null}

      {isDemoMode ? (
        <section className="top-panel demo-banner">
          <div>
            <span>Demo interactiva</span>
            <strong>Lo que ves son datos de ejemplo.</strong>
            <p>
              Puedes tocar jugadores, cambiar asistencia, revisar reservas, pagos, alineaciones, valoraciones y fichas. Cuando crees tu grupo real, la web empieza limpia.
            </p>
          </div>
          <button className="primary-button" type="button" onClick={() => showQuickForm("team")}>
            Crear mi grupo limpio
          </button>
        </section>
      ) : null}

      {needsLoginForSharedLink ? (
        <section className="top-panel shared-link-gate">
          <div>
            <span>{incomingSharedLink.hasMatch ? "Partido compartido" : "Invitación recibida"}</span>
            <strong>
              {incomingSharedLink.hasMatch
                ? "Inicia sesión para comprobar si perteneces al grupo."
                : "Para entrar al grupo necesitas identificarte."}
            </strong>
            <p>
              Guardamos este enlace mientras haces login.
              {incomingSharedLink.hasMatch
                ? " Al volver, el partido solo se abrirá si ya eres miembro del grupo."
                : " Al volver podrás decidir si aceptas la invitación."}
            </p>
          </div>
          <GoogleSignInButton label={googleButtonText} onClick={() => void signInWithGoogle()} disabled={!supabase || !googleClientId} />
        </section>
      ) : null}

      {sharedMatchAccessDenied ? (
        <section className="top-panel shared-link-gate shared-link-denied" role="alert">
          <div>
            <span>Partido privado</span>
            <strong>No puedes ver este partido porque no perteneces al grupo.</strong>
            <p>El enlace compartido no concede acceso. Un admin puede invitarte al partido o al grupo mediante una invitación distinta.</p>
          </div>
          <button className="secondary-button" type="button" onClick={() => window.location.assign("/")}>Volver</button>
        </section>
      ) : null}

      {renderPlayerAssessmentPanel()}

      {canUseAdminControls && activeMobileTab === "mercado" ? (
        <section className={`top-panel market-admin-panel ${activeMatch.publicOpen ? "public-open" : ""}`} id="mercado" aria-label="Configuración de mercado del partido">
          <div className="market-admin-header">
            <div>
              <span>Mercado</span>
              <strong>Configurar partido público</strong>
              <p>
                Solo admins y owner ven esta pantalla. Los jugadores normales siguen entrando al mercado público.
              </p>
            </div>
            <div className="market-admin-header-actions">
              <a href={marketScoutUrl("jugadores")}>Ver mercado público</a>
              <button type="button" onClick={() => navigateMobileTab("partido")}>
                Volver al partido
              </button>
            </div>
          </div>

          {matchConfigured ? (
            canConfigureMatchMarket ? (
              <>
                <div className="market-admin-summary">
                  <div>
                    <span>Faltan</span>
                    <strong>{missing}</strong>
                  </div>
                  <div>
                    <span>Plazas públicas</span>
                    <strong>{activeMatch.publicOpen ? publicOpenSlots : "-"}</strong>
                  </div>
                  <div>
                    <span>Solicitudes</span>
                    <strong>{pendingOpenMatchRequests.length}</strong>
                  </div>
                  <div>
                    <span>Estado</span>
                    <strong>{activeMatch.publicOpen ? "Publicado" : "Privado"}</strong>
                  </div>
                </div>

                <div className="public-match-options market-admin-options">
                  <label>
                    Plazas públicas
                    <input
                      min="1"
                      max={Math.max(missing, 1)}
                      type="number"
                      value={publicOpenSlots}
                      onChange={(event) =>
                        updateMatch({
                          ...activeMatch,
                          publicOpenSlots: Math.max(1, Math.min(Math.max(missing, 1), Math.floor(Number(event.target.value) || 1))),
                        })
                      }
                    />
                  </label>
                  <label>
                    Nivel mín.
                    <select
                      value={Math.round(publicMatchRating(activeMatch.publicMinRating, 0) * 10)}
                      onChange={(event) => updateMatch({ ...activeMatch, publicMinRating: Number(event.target.value) / 10 })}
                    >
                      {publicMatchRatingPointOptions.map((rating) => (
                        <option key={rating} value={rating}>{rating}</option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Nivel máx.
                    <select
                      value={Math.round(publicMatchRating(activeMatch.publicMaxRating, 10) * 10)}
                      onChange={(event) => updateMatch({ ...activeMatch, publicMaxRating: Number(event.target.value) / 10 })}
                    >
                      {publicMatchRatingPointOptions.map((rating) => (
                        <option key={rating} value={rating}>{rating}</option>
                      ))}
                    </select>
                  </label>
                  <label className="public-match-toggle">
                    <input
                      checked={activeMatch.publicRequiresApproval ?? true}
                      onChange={(event) => updateMatch({ ...activeMatch, publicRequiresApproval: event.target.checked })}
                      type="checkbox"
                    />
                    Requiere aceptar
                  </label>
                  <label className="public-match-toggle">
                    <input
                      checked={activeMatch.publicGuestsPay ?? true}
                      onChange={(event) => updateMatch({ ...activeMatch, publicGuestsPay: event.target.checked })}
                      type="checkbox"
                    />
                    Invitado paga
                  </label>
                  <div className="public-position-options" aria-label="Posiciones buscadas">
                    {publicMatchPositionOptions.map((position) => {
                      const selectedPositions = normalizePublicMatchPositions(activeMatch.publicPositions);
                      const selected = selectedPositions.includes(position);
                      return (
                        <label key={position}>
                          <input
                            checked={selected}
                            onChange={(event) => {
                              const nextPositions = event.target.checked
                                ? [...selectedPositions, position]
                                : selectedPositions.filter((item) => item !== position);
                              updateMatch({ ...activeMatch, publicPositions: nextPositions });
                            }}
                            type="checkbox"
                          />
                          {position}
                        </label>
                      );
                    })}
                  </div>
                </div>

                <div className="market-scout-actions market-admin-actions">
                  <a href={marketScoutUrl("jugadores")}>Buscar jugadores</a>
                  <button type="button" onClick={() => void publishOpenMatch()} disabled={missing <= 0 && !activeMatch.publicOpen}>
                    {activeMatch.publicOpen ? "Actualizar público" : "Abrir partido al público"}
                  </button>
                  {activeMatch.publicOpen ? (
                    <>
                      <a href={marketScoutUrl("partidos")}>Ver anuncio</a>
                      <button className="ghost-scout-button" type="button" onClick={() => void closeOpenMatch()}>
                        Cerrar público
                      </button>
                    </>
                  ) : null}
                </div>

                {openMatchRequestMessage ? <small className="sync-status sync-live">{openMatchRequestMessage}</small> : null}
              </>
            ) : (
              <div className="market-admin-empty">
                <strong>Este partido no admite mercado ahora.</strong>
                <span>Solo se puede publicar mientras la alineación está abierta y el partido no está finalizado.</span>
              </div>
            )
          ) : (
            <div className="market-admin-empty">
              <strong>Guarda el partido primero.</strong>
              <span>Cuando tenga campo, fecha y plazas, podrás abrirlo al mercado.</span>
            </div>
          )}
        </section>
      ) : null}

      {showPlayerImportGate && selectedImportCandidate ? (
        <section className="top-panel shared-link-gate profile-import-gate">
          <div className="profile-import-copy">
            <span>Ficha encontrada</span>
            <strong>Hemos encontrado {playerImportCandidates.length} ficha{playerImportCandidates.length === 1 ? "" : "s"} tuyas.</strong>
            <p>
              Te proponemos entrar con la mejor media. Se copian solo datos base; goles, partidos, forma, votos y lesiones empiezan limpios en este grupo.
            </p>
          </div>
          <div className="profile-import-card">
            <button
              className="profile-import-selected"
              onClick={() => setShowImportChoices((current) => !current)}
              type="button"
            >
              <span className="profile-import-avatar">
                {selectedImportCandidate.player.avatar ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={selectedImportCandidate.player.avatar} alt="" draggable={false} style={avatarImageStyle(selectedImportCandidate.player)} />
                ) : (
                  <b>+</b>
                )}
              </span>
              <span>
                <strong>{playerDisplayName(selectedImportCandidate.player)}</strong>
                <small>Media {overallScore(selectedImportCandidate.media)} · importada · {selectedImportCandidate.appearances} PJ</small>
                <small>{selectedImportCandidate.groupName}{selectedImportCandidate.inactive ? " · ya no está" : ""}</small>
              </span>
            </button>
            {showImportChoices ? (
              <div className="profile-import-options">
                {playerImportCandidates.map((candidate) => (
                  <button
                    className={candidate.key === selectedImportCandidate.key ? "selected" : ""}
                    key={candidate.key}
                    onClick={() => {
                      setSelectedImportCandidateKey(candidate.key);
                      setShowImportChoices(false);
                    }}
                    type="button"
                  >
                    <strong>{playerDisplayName(candidate.player)}</strong>
                    <span>{overallScore(candidate.media)} · {candidate.appearances} PJ · {candidate.groupName}{candidate.inactive ? " · inactiva" : ""}</span>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
          <div className="profile-import-actions">
            <button className="primary-button" type="button" onClick={() => void importOwnPlayerProfile(selectedImportCandidate)}>
              Entrar con esta ficha
            </button>
            <button className="ghost-form-button" type="button" onClick={() => setShowImportChoices((current) => !current)}>
              Elegir otra
            </button>
            <button className="ghost-form-button" type="button" onClick={() => void openOwnPlayerProfile()}>
              Crear ficha con test
            </button>
          </div>
        </section>
      ) : null}

      {needsProfileForSharedMatch ? (
        <section className="top-panel shared-link-gate profile-needed-gate">
          <div>
            <span>Último paso</span>
            <strong>Crea tu ficha para poder marcar “Voy”.</strong>
            <p>
              El test inicial crea la ficha vinculada a tu cuenta. A partir de ahí solo tú y los admins podréis editar tus datos.
            </p>
          </div>
          <button className="primary-button" type="button" onClick={() => void openOwnPlayerProfile()}>
            Hacer test inicial
          </button>
        </section>
      ) : null}

      {showSubscriptionPanel ? (
        <section className={groupBillingLocked ? "top-panel billing-panel billing-locked" : "top-panel billing-panel"} ref={billingPanelRef}>
          <div className="billing-copy">
            <span>Suscripción del grupo</span>
            <strong>{groupBillingLocked ? "Prueba terminada" : billingStatusLabel(currentTeam)}</strong>
            <p>
              {billingActive
                ? `Plan ${billingPeriodLabel(currentTeam?.billingInterval)} activo. El grupo puede seguir creando y finalizando partidos.`
                : `Cada grupo puede finalizar ${freeTrialMatchLimit} partidos gratis. Después, el owner activa un plan para seguir usando el histórico, ranking y organización.`}
            </p>
          </div>
          <div className="billing-metrics">
            <div>
              <span>Prueba usada</span>
              <strong>{billingTrialUsed}/{freeTrialMatchLimit}</strong>
            </div>
            <div>
              <span>Quedan</span>
              <strong>{billingActive ? "Ilimitados" : billingTrialRemaining}</strong>
            </div>
            <div>
              <span>Plan</span>
              <strong>{billingPeriodLabel(currentTeam?.billingInterval)}</strong>
            </div>
          </div>
          {canManageBilling ? (
            <div className="billing-actions">
              {!billingActive ? (
                <>
                  <button type="button" onClick={() => void startBillingCheckout("month")} disabled={Boolean(billingLoading)}>
                    {billingLoading === "month" ? "Abriendo..." : "Mensual 5,99 €/mes"}
                  </button>
                  <button type="button" onClick={() => void startBillingCheckout("year")} disabled={Boolean(billingLoading)}>
                    {billingLoading === "year" ? "Abriendo..." : "Anual 64,99 €/año"}
                  </button>
                </>
              ) : null}
              {currentTeam?.stripeCustomerId ? (
                <button type="button" onClick={() => void openBillingPortal()} disabled={Boolean(billingLoading)}>
                  {billingLoading === "portal" ? "Abriendo..." : "Gestionar plan"}
                </button>
              ) : null}
            </div>
          ) : (
            <small className="billing-message">Solo el owner del grupo puede activar o gestionar el plan.</small>
          )}
          {billingMessage ? <small className="billing-message billing-error">{billingMessage}</small> : null}
        </section>
      ) : null}

      {showSettings && canUseAdminControls ? (
        <section className="top-panel settings-panel" ref={settingsPanelRef}>
          <div className="settings-panel-header">
            <div>
              <span>Configuración</span>
              <strong>Grupo de pachangas</strong>
            </div>
            <small>Admins · permisos solo owner</small>
          </div>
          <button className="settings-reward-demo-button" type="button" onClick={() => setRewardBoxDemoOpen(true)}>
            <span>Animación de logro</span>
            <small>Abrir prueba visual</small>
          </button>
          <label>
            Instrucciones
            <input value={settingsDraft.subtitle} disabled={!canUseAdminControls} onChange={(event) => setSettingsDraft({ ...settingsDraft, subtitle: event.target.value })} />
          </label>
          <div className="palette-field">
            <span>Color equipo 1</span>
            <div className="color-select">
              <span style={{ background: settingsDraft.teamAColor }} />
              <select value={settingsDraft.teamAColor} disabled={!canUseAdminControls} onChange={(event) => setSettingsDraft({ ...settingsDraft, teamAColor: event.target.value })}>
                {teamPalette.map((color) => (
                  <option key={`team-a-${color.value}`} value={color.value}>{color.name}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="palette-field">
            <span>Color equipo 2</span>
            <div className="color-select">
              <span style={{ background: settingsDraft.teamBColor }} />
              <select value={settingsDraft.teamBColor} disabled={!canUseAdminControls} onChange={(event) => setSettingsDraft({ ...settingsDraft, teamBColor: event.target.value })}>
                {teamPalette.map((color) => (
                  <option key={`team-b-${color.value}`} value={color.value}>{color.name}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="subscription-settings">
            <label className="settings-toggle">
              Valoraciones entre jugadores
              <span>
                <input
                  type="checkbox"
                  checked={ratingsEnabled}
                  disabled={!canManageTeam}
                  onChange={(event) => void setGroupRatingsEnabled(event.target.checked)}
                />
                {ratingsEnabled ? "Activadas" : "Desactivadas"}
              </span>
            </label>
            <label className="settings-toggle">
              Aporte app por Bizum
              <span>
                <input
                  type="checkbox"
                  checked={settingsDraft.subscriptionContributionEnabled}
                  disabled={!canUseAdminControls}
                  onChange={(event) => setSettingsDraft({ ...settingsDraft, subscriptionContributionEnabled: event.target.checked })}
                />
                Repartir entre jugadores activos
              </span>
            </label>
            <label>
              Periodo
              <select
                value={settingsDraft.subscriptionContributionPeriod}
                disabled={!canUseAdminControls}
                onChange={(event) => setSettingsDraft({ ...settingsDraft, subscriptionContributionPeriod: event.target.value as BillingInterval })}
              >
                <option value="year">Anual recomendado</option>
                <option value="month">Mensual</option>
              </select>
            </label>
            <label>
              Mensual €
              <input
                type="number"
                min="0"
                step="0.01"
                value={settingsDraft.subscriptionContributionMonthlyAmount}
                disabled={!canUseAdminControls}
                onChange={(event) => setSettingsDraft({ ...settingsDraft, subscriptionContributionMonthlyAmount: Number(event.target.value) })}
              />
            </label>
            <label>
              Anual €
              <input
                type="number"
                min="0"
                step="0.01"
                value={settingsDraft.subscriptionContributionYearlyAmount}
                disabled={!canUseAdminControls}
                onChange={(event) => setSettingsDraft({ ...settingsDraft, subscriptionContributionYearlyAmount: Number(event.target.value) })}
              />
            </label>
            <p>Esta cuota no se suma al campo. Es una referencia aparte para que los jugadores aporten por Bizum al owner.</p>
          </div>
          <div className="saved-venues-panel">
            <div className="backup-title">
              <div>
                <span>Campos guardados</span>
                <strong>{venues.length}</strong>
              </div>
            </div>
            <p>Borra campos que ya no usáis o que se crearon mal. Los partidos históricos conservan el nombre del lugar.</p>
            {venues.length === 0 ? <small className="backup-message">Todavía no hay campos guardados.</small> : null}
            {venues.length > 0 ? (
              <div className="saved-venue-list">
                {venues.map((venue) => {
                  const usage = venueUsage(venue.id);

                  return (
                    <article key={venue.id}>
                      <div>
                        <strong>{venue.name}</strong>
                        <span>{venue.address ?? venue.city ?? "Dirección sin completar"}</span>
                        <small>
                          {venue.kind ? matchKinds[venue.kind].label : "Sin modalidad"} · {venue.defaultCost.toFixed(0)} €
                          {usage.open || usage.closed ? ` · ${usage.open} abiertos · ${usage.closed} históricos` : ""}
                        </small>
                      </div>
                      <button
                        className="trash-icon-button venue-delete-button"
                        type="button"
                        onClick={() => void deleteVenue(venue.id)}
                        title={`Borrar ${venue.name}`}
                        aria-label={`Borrar campo ${venue.name}`}
                      >
                        <TrashLogo />
                      </button>
                    </article>
                  );
                })}
              </div>
            ) : null}
          </div>
          {canManageTeam ? (
            <div className="owner-permissions-panel">
              <div className="backup-title">
                <div>
                  <span>Miembros y permisos</span>
                  <strong>{canManageRoles ? "Owner" : "Admin"}</strong>
                </div>
              </div>
              <p>{canManageRoles ? "Cambia roles, transfiere la propiedad o elimina miembros registrados." : "Puedes eliminar jugadores. Solo el owner cambia admins o transfiere la propiedad."}</p>
              <div className="member-admin-list">
                {teamMembers.map((member) => (
                  <label key={`settings-member-${member.userId}`}>
                    <strong>
                      {member.displayName}
                      {member.userId === currentUserId ? " (tú)" : ""}
                    </strong>
                    <span className="member-admin-actions">
                      <select
                        value={member.role}
                        disabled={!canManageRoles || member.role === "owner" || member.userId === currentUserId}
                        onChange={(event) => void updateMemberRole(member, event.target.value as MemberRole)}
                      >
                        {member.role === "owner" ? <option value="owner">Owner / Admin</option> : null}
                        <option value="admin">Admin</option>
                        <option value="player">Jugador</option>
                      </select>
                      {canManageRoles && member.role !== "owner" && member.userId !== currentUserId ? (
                        <button type="button" onClick={() => void transferTeamOwnership(member)}>Hacer owner</button>
                      ) : null}
                      {member.role !== "owner" && member.userId !== currentUserId && (canManageRoles || member.role === "player") ? (
                        <button className="danger-light-button" type="button" onClick={() => void removeRegisteredMember(member)}>Eliminar</button>
                      ) : null}
                    </span>
                  </label>
                ))}
              </div>
              {canManageRoles ? (
                <div className="admin-invite-row settings-admin-invite-row">
                  <span>Invitar como admin (no owner)</span>
                  <div>
                    <button type="button" onClick={() => void createAdminInvite()} disabled={!remoteGroupId}>
                      Crear link
                    </button>
                    <button className="copy-icon-button" type="button" onClick={() => void copyAdminInvite()} disabled={!remoteGroupId} title="Copiar invitación como admin, sin permisos de owner" aria-label="Copiar invitación como admin, sin permisos de owner">
                      <CopyLogo />
                    </button>
                    <button className="whatsapp-icon-button" type="button" onClick={() => void shareAdminInviteWhatsApp()} disabled={!remoteGroupId} title="Enviar invitación como admin por WhatsApp" aria-label="Enviar invitación como admin por WhatsApp">
                      <WhatsAppLogo />
                    </button>
                  </div>
                  {adminInviteToken ? <small>Invitación admin lista</small> : null}
                </div>
              ) : null}
            </div>
          ) : null}
          <div className="backup-panel">
            <div className="backup-title">
              <div>
                <span>Copias de seguridad</span>
                <strong>Rescate de equipos</strong>
              </div>
              <div className="backup-actions">
                <button type="button" onClick={() => void loadTeamBackups()} disabled={!isRegisteredUser || backupsLoading}>
                  Recargar
                </button>
                <button type="button" onClick={() => void createManualBackup()} disabled={!canUseAdminControls}>
                  Crear copia
                </button>
              </div>
            </div>
            <p>
              Al guardar o finalizar un partido se crea una copia en el servidor. Se conservan solo las 3 últimas por grupo; al crear una nueva se elimina la más antigua.
            </p>
            {backupMessage ? <small className="backup-message">{backupMessage}</small> : null}
            {backupsLoading ? <small className="backup-message">Cargando copias...</small> : null}
            {!isRegisteredUser ? <small className="backup-message">Entra con Google para ver tus copias.</small> : null}
            {isRegisteredUser && teamBackups.length === 0 && !backupsLoading ? (
              <small className="backup-message">Todavía no hay copias guardadas.</small>
            ) : null}
            {teamBackups.length > 0 ? (
              <div className="backup-list">
                {teamBackups.map((backup) => (
                  <article key={backup.id}>
                    <div>
                      <strong>{backup.groupName}</strong>
                      <span>{backupReasonLabels[backup.reason] ?? backup.reason} · {new Date(backup.createdAt).toLocaleString("es-ES", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}</span>
                      <small>{backup.playerCount} jugadores · {backup.matchCount} partidos{backup.teamCode ? ` · ID ${backup.teamCode}` : ""}</small>
                    </div>
                    <button type="button" onClick={() => void restoreTeamBackup(backup)}>
                      Restaurar
                    </button>
                  </article>
                ))}
              </div>
            ) : null}
          </div>
          <div className="settings-actions">
            <button className="panel-hide-button" type="button" onClick={() => void saveSettingsPanel()}>
              Guardar
            </button>
            <button className="panel-cancel-button" type="button" onClick={closeSettingsPanelWithoutSave}>
              Cerrar sin guardar
            </button>
          </div>
        </section>
      ) : null}

      <section className={sharedLinkContentBlocked ? "app-shell gated-shell" : "app-shell"} data-match-manager-pane={selectedMatchManagerPane}>
        <nav className="match-manager-subnav" aria-label="Secciones del partido en modo juego">
          {matchManagerPanes.map((pane) => (
            <button
              aria-current={selectedMatchManagerPane === pane ? "page" : undefined}
              className={selectedMatchManagerPane === pane ? "active" : ""}
              key={pane}
              onClick={() => setActiveMatchManagerPane(pane)}
              type="button"
            >
              <span>{matchManagerPaneLabel(pane)}</span>
            </button>
          ))}
          {selectedMatchManagerPane === "alineacion" && !matchFinalized ? (
            <div className="lineup-side-tools" aria-label="Herramientas de alineación">
              <span className="lineup-side-tools-kicker">Herramientas</span>
              <div className="lineup-side-actions">
                <button type="button" onClick={applyRandomTeams} disabled={!canEditLineup}>Aleatorio</button>
                <button type="button" onClick={applyBalancedTeams} disabled={!canEditLineup}>Equilibrado</button>
                {canUseAdminControls && matchConfigured && !matchFinalized ? (
                  <button type="button" onClick={() => void toggleLineupClosed()}>
                    {lineupClosed ? "Abrir" : "Cerrar"}
                  </button>
                ) : null}
              </div>
            </div>
          ) : null}
          {selectedMatchManagerPane === "proximo" && matchMemberShareBox ? (
            <div className="match-side-share" aria-label="Compartir partido">
              {matchMemberShareBox}
            </div>
          ) : null}
        </nav>
        <div className={matchFinalized ? "match-active-context finalized" : "match-active-context"} aria-label="Partido activo">
          <span>{matchContextKind}</span>
          <span className="match-active-kind">{matchKinds[activeKind].label}</span>
          <div>
            <strong>{activeMatch.title || matchKinds[activeKind].label}</strong>
            <small>{matchSummaryDate(activeMatch.date)} · {activeMatch.place}</small>
          </div>
          {canToggleLineupFromContext ? (
            <button
              aria-label={lineupClosed ? "Abrir alineación" : "Cerrar alineación"}
              aria-pressed={lineupClosed}
              className="match-context-status-button"
              onClick={() => void toggleLineupClosed()}
              type="button"
            >
              {matchContextStatus}
            </button>
          ) : (
            <b>{matchContextStatus}</b>
          )}
        </div>
        <aside className="panel match-list" aria-label="Partidos">
          <div className="panel-title">
            <span>Próximos partidos</span>
            <strong>{openMatches.length}</strong>
          </div>
          {openMatches.length === 0 ? <p className="empty-copy">Crea tu primer partido desde “Crear”.</p> : null}
          <div className="next-match-rail">
            {openMatches.map((match) => {
              const matchTitle = matchTitleWithoutTrailingTime(match.title) || matchKinds[match.kind ?? "futbol7"].label;
              return (
                <div className="match-row" key={match.id}>
                  <button
                    className={match.id === activeMatch.id ? "match-item active" : "match-item"}
                    onClick={() => openMatchFromInicio(match.id, "proximo")}
                    type="button"
                  >
                    <span>{matchTitle}</span>
                    <small className="match-item-kind">{matchKinds[match.kind ?? "futbol7"].label}</small>
                    <small className="match-item-date">{matchDayLabel(match.date)} · {matchTimeLabel(match.date)}</small>
                    <small className="match-item-place">{match.place || "Campo por confirmar"}</small>
                  </button>
                </div>
              );
            })}
          </div>
          <div className="side-history">
            <div className="panel-title compact-title">
              <span>Historial</span>
              <strong>{filteredClosedMatches.length}</strong>
            </div>
            <label className="history-season-filter">
              Temporada
              <select value={activeHistorySeason} onChange={(event) => setHistorySeason(event.target.value)}>
                <option value="all">Todas</option>
                {rankingSeasons.map((season) => (
                  <option key={season} value={season}>{season}</option>
                ))}
              </select>
            </label>
            <div className="history">
              {filteredClosedMatches.length === 0 ? <p className="empty-copy">No hay partidos en esta temporada.</p> : null}
              {filteredClosedMatches.map((match, index) => {
                const currentMonth = monthLabel(match.date);
                const previousMonth = index > 0 ? monthLabel(filteredClosedMatches[index - 1].date) : "";

                return (
                  <Fragment key={match.id}>
                    {currentMonth !== previousMonth ? <div className="history-month">{currentMonth}</div> : null}
                    <button
                      className={match.teamPhoto ? "history-item has-photo" : "history-item"}
                      onClick={() => openMatchFromInicio(match.id, "resultado")}
                      type="button"
                    >
                      {match.teamPhoto ? (
                        <span
                          className="history-photo"
                          onClick={(event) => {
                            event.stopPropagation();
                            setMatchPhotoPreview({ src: match.teamPhoto!, title: match.title });
                          }}
                          title={`Ver foto de ${match.title}`}
                        >
                          <img src={match.teamPhoto} alt="" />
                        </span>
                      ) : null}
                      <div>
                        <strong>{match.title}</strong>
                        <small className="history-item-kind">{matchKinds[match.kind ?? "futbol7"].label}</small>
                      </div>
                      <span className="history-score-badge">
                        <b>{match.scoreA} - {match.scoreB}</b>
                        <small>{new Date(match.date).toLocaleDateString("es-ES", { day: "2-digit", month: "short" })}</small>
                      </span>
                      <small>{match.place}</small>
                    </button>
                  </Fragment>
                );
              })}
            </div>
          </div>
        </aside>

        <section className={mainPanelClassName} id="partido" ref={matchPanelRef}>
          {showMatchAdminPanel ? (
            <>
              {matchFinalized ? (
                <div className="match-admin-hub match-manager-admin-block historical-match-admin-hub" aria-label="Administración del partido histórico">
                  <section className="match-admin-action-panel match-admin-create-panel historical-match-admin-panel">
                    <div className="match-admin-action-heading">
                      <span>Archivo</span>
                      <strong>Partido finalizado</strong>
                    </div>
                    <div className="match-admin-create-grid historical-match-admin-actions">
                      <button type="button" onClick={() => window.location.assign(`/admin/conduct?groupId=${encodeURIComponent(remoteGroupId ?? "")}&matchId=${encodeURIComponent(activeMatch.id)}`)}>
                        <span>Cerrar asistencia</span>
                        <small>Jugó, baja o no-show</small>
                      </button>
                      <button className="match-admin-danger-button" type="button" onClick={() => deleteMatch(activeMatch.id)} disabled={!canUseAdminControls}>
                        <span>Borrar partido</span>
                        <small>Eliminar histórico</small>
                      </button>
                    </div>
                  </section>
                </div>
              ) : (
                <>
              <div className={canEditMatchSettings ? "match-editor match-manager-admin-block" : "match-editor readonly-editor match-manager-admin-block"}>
                {matchFinalized ? <span className="admin-only-badge">Partido finalizado</span> : null}
                {!matchConfigured && !matchFinalized ? <span className="admin-only-badge draft-badge">Borrador</span> : null}
                <label className="match-field-control">
                  Campo
                  <select value={activeMatch.venueId ?? ""} onChange={(event) => selectVenue(event.target.value)} disabled={!canEditMatchSettings}>
                    <option value="" disabled>Selecciona campo</option>
                    {venues.map((venue) => (
                      <option key={venue.id} value={venue.id}>{venue.name}</option>
                    ))}
                  </select>
                </label>
                <label className="match-date-control">
                  Fecha
                  <input
                    type="date"
                    value={matchDatePart(activeMatch.date)}
                    disabled={!canEditMatchSettings}
                    onKeyDown={(event) => {
                      if (event.key === "Enter" || event.key === " " || event.key === "ArrowDown") {
                        requestNativeInputPicker(event.currentTarget);
                      }
                    }}
                    onPointerDown={(event) => {
                      if (event.button === 0) requestNativeInputPicker(event.currentTarget);
                    }}
                    onChange={(event) => {
                      const nextDate = combineMatchDateTime(event.target.value, activeMatch.date);
                      updateMatchSettings({ ...activeMatch, date: nextDate, season: seasonKey(nextDate) });
                    }}
                  />
                </label>
                <label className="match-time-control">
                  Hora
                  <input
                    type="time"
                    step={600}
                    value={matchTimePart(activeMatch.date)}
                    disabled={!canEditMatchSettings}
                    onKeyDown={(event) => {
                      if (event.key === "Enter" || event.key === " " || event.key === "ArrowDown") {
                        requestNativeInputPicker(event.currentTarget);
                      }
                    }}
                    onPointerDown={(event) => {
                      if (event.button === 0) requestNativeInputPicker(event.currentTarget);
                    }}
                    onChange={(event) => {
                      const nextDate = combineMatchDateTime(matchDatePart(activeMatch.date), event.target.value);
                      updateMatchSettings({ ...activeMatch, date: nextDate, season: seasonKey(nextDate) });
                    }}
                  />
                </label>
                <label className="match-kind-control">
                  Modalidad
                  <select value={activeKind} onChange={(event) => changeKind(event.target.value as MatchKind)} disabled={!canEditMatchSettings}>
                    {Object.entries(matchKinds).map(([kind, config]) => (
                      <option key={kind} value={kind}>{config.label}</option>
                    ))}
                  </select>
                </label>
                <label className="reserve-toggle">
                  Reservas
                  <span className="reserve-toggle-box">
                    <input
                      type="checkbox"
                      checked={Boolean(activeMatch.reservesAttend)}
                      disabled={!canEditMatchSettings}
                      onChange={(event) =>
                        updateMatchSettings({
                          ...activeMatch,
                          reservesAttend: event.target.checked,
                          reserveLimit: event.target.checked ? Math.max(1, activeMatch.reserveLimit ?? 2) : 0,
                        })
                      }
                    />
                    Van y pagan
                  </span>
                </label>
                <label>
                  Max reservas
                  <input
                    type="number"
                    min="0"
                    value={reserveLimitDraftValue}
                    disabled={!canEditMatchSettings || !activeMatch.reservesAttend}
                    onFocus={() => {
                      setEditingMatchNumberField("reserveLimit");
                      setMatchReserveLimitDraft(String(activeMatch.reserveLimit ?? 0));
                    }}
                    onBlur={commitReserveLimitDraft}
                    onChange={(event) => editReserveLimitDraft(event.target.value)}
                  />
                </label>
                <label className="match-price-control">
                  Precio
                  <input
                    type="number"
                    min="0"
                    value={fieldCostDraftValue}
                    disabled={!canEditMatchSettings}
                    onFocus={() => {
                      setEditingMatchNumberField("fieldCost");
                      setMatchFieldCostDraft(String(fieldCost));
                    }}
                    onBlur={commitFieldCostDraft}
                    onChange={(event) => editFieldCostDraft(event.target.value)}
                  />
                </label>
                {!matchFinalized ? (
                  <button className="save-match-button" type="button" onClick={() => void saveMatchConfiguration()} disabled={!matchCanBeSaved || matchConfigured}>
                    {matchConfigured ? "Guardado" : "Guardar partido"}
                  </button>
                ) : null}
              </div>

              <div className="match-admin-hub match-manager-admin-block" aria-label="Administración del partido">
                {matchAdminInviteBox ? (
                  <section className="match-admin-action-panel match-admin-invite-panel">
                    <div className="match-admin-action-heading">
                      <span>Invitar al partido</span>
                      <strong>Acceso limitado</strong>
                    </div>
                    <p>La invitación permite ver este partido sin convertir al jugador en miembro ni administrador del grupo.</p>
                    {matchAdminInviteBox}
                  </section>
                ) : null}
                <section className={`match-admin-action-panel match-admin-market-panel ${activeMatch.publicOpen ? "public-open" : ""}`}>
                  <div className="match-admin-action-heading">
                    <span>Mercado del partido</span>
                    <strong>{activeMatch.publicOpen ? "Publicado" : "Privado"}</strong>
                  </div>
                  <div className="match-admin-filter-strip" aria-label="Filtros del partido activo">
                    <span>{matchKinds[activeKind].label}</span>
                    <span>{missing} plaza{missing === 1 ? "" : "s"}</span>
                    <span>{activeVenue?.city || activeMatch.place || "Zona pendiente"}</span>
                  </div>
                  <div className="match-admin-market-stats">
                    <div>
                      <span>Solicitudes</span>
                      <strong>{pendingOpenMatchRequests.length}</strong>
                    </div>
                    <div>
                      <span>Públicas</span>
                      <strong>{activeMatch.publicOpen ? publicOpenSlots : "-"}</strong>
                    </div>
                  </div>
                  <div className="match-admin-actions-row">
                    <a
                      className={!matchConfigured ? "disabled" : ""}
                      href={marketScoutUrl("jugadores")}
                      aria-disabled={!matchConfigured}
                      onClick={(event) => {
                        if (!matchConfigured) event.preventDefault();
                      }}
                    >
                      Buscar jugadores
                    </a>
                    <button
                      type="button"
                      onClick={() => void publishOpenMatch()}
                      disabled={!canConfigureMatchMarket || (missing <= 0 && !activeMatch.publicOpen)}
                    >
                      {activeMatch.publicOpen ? "Actualizar mercado" : "Abrir al mercado"}
                    </button>
                    {activeMatch.publicOpen ? (
                      <button className="ghost-scout-button" type="button" onClick={() => void closeOpenMatch()}>
                        Cerrar mercado
                      </button>
                    ) : null}
                    <button type="button" onClick={openMarketConfiguration} disabled={!matchConfigured}>
                      Configurar filtros
                    </button>
                  </div>
                  {openMatchRequestMessage ? <small className="sync-status sync-live">{openMatchRequestMessage}</small> : null}
                </section>

                <section className="match-admin-action-panel match-admin-create-panel">
                  <div className="match-admin-action-heading">
                    <span>Crear</span>
                    <strong>Altas rápidas</strong>
                  </div>
                  <div className="match-admin-create-grid">
                    <button type="button" onClick={() => showQuickForm("venue")} disabled={!canUseAdminControls}>
                      <span>Campo</span>
                      <small>Precio y modalidad</small>
                    </button>
                    <button type="button" onClick={() => void openCreatePlayerProfile()} disabled={!canUseAdminControls && (!hasRealTeam || !isRegisteredUser)}>
                      <span>Jugador</span>
                      <small>Ficha del grupo</small>
                    </button>
                    <button type="button" onClick={createMatch} disabled={!canUseAdminControls}>
                      <span>Nuevo partido</span>
                      <small>Borrador siguiente</small>
                    </button>
                    <button className="match-admin-danger-button" type="button" onClick={() => deleteMatch(activeMatch.id)} disabled={!canUseAdminControls}>
                      <span>Borrar partido</span>
                      <small>Eliminar actual</small>
                    </button>
                    <button type="button" onClick={() => setRewardBoxDemoOpen(true)} disabled={!canUseAdminControls}>
                      <span>Animación de logro</span>
                      <small>Prueba visual</small>
                    </button>
                  </div>
                </section>
              </div>
                </>
              )}

              {!matchConfigured && !matchFinalized ? (
                <div className="draft-match-note">
                  <span>Partido sin guardar</span>
                  <strong>Configura campo, fecha, modalidad y precio. Al guardar se activan confirmaciones, compartir y alineación.</strong>
                </div>
              ) : null}
              {registrationLockedByPreviousMatch && previousPendingMatch ? (
                <div className="registration-locked-note">
                  <span>Inscripción pendiente</span>
                  <strong>
                    Se abrirá cuando pase {previousPendingMatch.title || "el partido anterior"} ({matchSummaryDate(previousPendingMatch.date)}).
                  </strong>
                </div>
              ) : null}
            </>
          ) : null}

          {matchConfigured && !matchFinalized ? (
            <section className={`weather-card weather-card-${matchWeatherStatus}`} aria-label="Previsión del tiempo">
              {matchWeatherStatus === "unavailable" && matchWeatherMessage.startsWith("Previsión del tiempo disponible") ? (
                <p className="weather-availability-message">{matchWeatherMessage}</p>
              ) : (
                <>
                  <div className="weather-card-main">
                    <WeatherIcon status={matchWeatherStatus} weather={matchWeather} />
                    <div className="weather-summary">
                      <span>Tiempo previsto</span>
                      <strong>
                        {matchWeatherStatus === "ready" && matchWeather && matchWeather.temperature !== null
                          ? `${Math.round(matchWeather.temperature)}°`
                          : matchWeatherStatus === "loading"
                            ? "Consultando"
                            : "Sin previsión"}
                      </strong>
                    </div>
                    <p>
                      {matchWeatherStatus === "ready" && matchWeather
                        ? matchWeather.condition
                        : matchWeatherStatus === "loading"
                          ? "Buscando la previsión más cercana a la hora del partido."
                          : matchWeatherMessage || "Guarda un campo con ubicación verificada para activar esta previsión."}
                    </p>
                  </div>
                  {matchWeatherStatus === "ready" && matchWeather ? (
                    <>
                      <div className="weather-metrics">
                        <span><WeatherMetricIcon kind="feels" /> Sens. {matchWeather.feelsLike === null ? "-" : `${Math.round(matchWeather.feelsLike)}°`}</span>
                        <span><WeatherMetricIcon kind="rain" /> Lluvia {matchWeather.precipitationProbability === null ? "-" : `${Math.round(matchWeather.precipitationProbability)}%`}</span>
                        <span><WeatherMetricIcon kind="wind" /> Viento {matchWeather.windKmh === null ? "-" : `${Math.round(matchWeather.windKmh)} km/h`}</span>
                        <span><WeatherMetricIcon kind="humidity" /> Hum. {matchWeather.humidity === null ? "-" : `${Math.round(matchWeather.humidity)}%`}</span>
                      </div>
                    </>
                  ) : null}
                </>
              )}
            </section>
          ) : null}

          {!matchFinalized ? (
            <div className="stats-row">
              <div>
                <span>Confirmados</span>
                <strong>{confirmedPlayers.length}/{activeMatch.targetPlayers}</strong>
              </div>
              <div>
                <span>Reservas</span>
                <strong>{activeMatch.reservesAttend ? `${reservePlayers.length}/${reserveLimit}` : "No"}</strong>
              </div>
              <div>
                <span>Espera</span>
                <strong>{waitingPlayers.length}</strong>
              </div>
              <div>
                <span>Duda</span>
                <strong>{doubtfulCount}</strong>
              </div>
              <div>
                <span>Campo</span>
                <strong>{fieldCost.toFixed(0)} €</strong>
              </div>
              {siteSettings.subscriptionContributionEnabled ? (
                <div>
                  <span>App</span>
                  <strong>{subscriptionContributionPerPlayer.toFixed(2)} €</strong>
                </div>
              ) : null}
              <div>
                <span>Paga</span>
                <strong>{paymentReady ? payer?.name ?? "-" : "-"}</strong>
              </div>
              <div className="payment-per-person-stat">
                <span>Pago por persona</span>
                <strong>{paymentReady ? `${sharePerPlayer.toFixed(2)} €` : "-"}</strong>
              </div>
              <div>
                <span>Pagados</span>
                <strong>{paymentReady ? `${paidCount}/${payingParticipantIds.length}` : "-"}</strong>
              </div>
            </div>
          ) : null}

          {paymentReady && payer && !matchFinalized ? (
            <div className="payer-note">
              <span>Turno de pago</span>
              <strong>{playerDisplayName(payer)} adelanta el campo. Bizum: {payer.phone || "sin telefono"} · {sharePerPlayer.toFixed(2)} € por persona</strong>
            </div>
          ) : null}

          {siteSettings.subscriptionContributionEnabled && activeRosterCount > 0 ? (
            <div className="payer-note subscription-contribution-note">
              <span>Aporte app por Bizum</span>
              <strong>
                Suscripción {subscriptionContributionLabel}: {subscriptionContributionAmount.toFixed(2)} € entre {activeRosterCount} jugadores activos · {subscriptionContributionPerPlayer.toFixed(2)} € para {ownerContributionRecipient}
              </strong>
            </div>
          ) : null}

          {showMatchRoster ? (
            <>
              {canUseAdminControls && openMatchRequests.length > 0 ? (
                <section className="open-match-requests-panel" aria-label="Solicitudes del mercado">
                  <div className="open-match-requests-title">
                    <span>Solicitudes del mercado</span>
                    <strong>{pendingOpenMatchRequests.length} pendiente{pendingOpenMatchRequests.length === 1 ? "" : "s"}</strong>
                  </div>
                  <div className="open-match-request-list">
                    {openMatchRequests.map((request) => {
                      const requestAge = playerAge(request.birthDate, currentDateValue);
                      const requestPending = request.status === "pending";
                      const requestStatusLabel = request.status === "accepted"
                        ? "Aceptado"
                        : request.status === "rejected"
                          ? "Rechazado"
                          : request.status === "cancelled"
                            ? "Cancelado"
                            : "Pendiente";

                      return (
                        <article className={`open-match-request-card request-${request.status}`} key={request.id}>
                          <span className="request-avatar">
                            {request.avatar ? (
                              // eslint-disable-next-line @next/next/no-img-element
                              <img src={request.avatar} alt="" draggable={false} style={avatarImageStyle(request)} />
                            ) : (
                              <b>+</b>
                            )}
                          </span>
                          <div>
                            <strong>
                              {request.requesterName}
                              {requestAge !== null ? <em>{requestAge} años</em> : null}
                            </strong>
                            <small>
                              {request.goalkeeperOnly ? "Portero fijo" : request.position} · Media {overallScore(request.media)} · Solicitud {joinedAtLabel(request.requestedAt)}
                            </small>
                          </div>
                          <div className="request-actions">
                            {requestPending ? (
                              <>
                                <button type="button" onClick={() => void reviewOpenMatchRequest(request, "accepted")}>Aceptar</button>
                                <button className="danger-light-button" type="button" onClick={() => void reviewOpenMatchRequest(request, "rejected")}>Rechazar</button>
                              </>
                            ) : (
                              <span>{requestStatusLabel}</span>
                            )}
                          </div>
                        </article>
                      );
                    })}
                  </div>
                  {openMatchRequestMessage ? <small className="sync-status sync-live">{openMatchRequestMessage}</small> : null}
                </section>
              ) : null}

              <div
                className="next-match-roster-rail"
                aria-label={matchFinalized ? "Jugadores del partido histórico" : "Jugadores del próximo partido"}
                onClickCapture={cancelRosterRailClick}
                onPointerCancel={finishRosterRailDrag}
                onPointerDown={startRosterRailDrag}
                onPointerMove={moveRosterRailDrag}
                onPointerUp={finishRosterRailDrag}
                onWheel={handleRosterRailWheel}
              >
                <div className="team-player-column team-a-column">
                  <div className="team-column-title">
                    <span>Equipo 1</span>
                    <strong>{suggested.teamA.length}</strong>
                  </div>
                  {sortedTeamA.map((player) => renderPlayerCard(player, "A"))}
                </div>
                <div className="team-player-column team-b-column">
                  <div className="team-column-title">
                    <span>Equipo 2</span>
                    <strong>{suggested.teamB.length}</strong>
                  </div>
                  {sortedTeamB.map((player) => renderPlayerCard(player, "B"))}
                </div>

                {showReserveRosterColumn ? (
                  <div className="team-player-column status-roster-column reserve-roster-column next-match-reserve-section">
                    <div className="team-column-title">
                      <span>Reservas</span>
                      <strong>{reservePlayers.length}/{reserveLimit}</strong>
                    </div>
                    {reservePlayers.length > 0 ? reservePlayers.map((player) => renderPlayerCard(player, undefined, "reserve")) : <p className="empty-copy">No hay reservas apuntados.</p>}
                  </div>
                ) : null}

                {showWaitingRosterColumn ? (
                  <div className="team-player-column status-roster-column waiting-roster-column next-match-waiting-section">
                    <div className="team-column-title">
                      <span>Lista de espera</span>
                      <strong>{waitingPlayers.length}</strong>
                    </div>
                    {waitingPlayers.map((player) => renderPlayerCard(player, undefined, "waiting"))}
                  </div>
                ) : null}

                {showStatusRosterColumn ? (
                  <div className="team-player-column status-roster-column other-status-roster-column next-match-status-section">
                    <div className="team-column-title">
                      <span>Otros estados</span>
                      <strong>{nextMatchStatusCount}</strong>
                    </div>
                    {nextMatchStatusGroups.length > 0 ? (
                      <div className="next-match-status-groups">
                        {nextMatchStatusGroups.map((group) => (
                          <section className={`next-match-status-group status-group-${group.id}`} key={group.id}>
                            <div className="status-group-title">
                              <span>{group.title}</span>
                              <strong>{group.players.length}</strong>
                            </div>
                            <div className="player-grid reserve-player-grid">
                              {group.players.map((player) => renderPlayerCard(player))}
                            </div>
                          </section>
                        ))}
                      </div>
                    ) : (
                      <p className="empty-copy">Todos tienen estado claro.</p>
                    )}
                  </div>
                ) : null}
              </div>
            </>
          ) : null}
        </section>

        <aside className="panel teams-panel lineup-panel" id="alineacion">
          <div className="panel-title teams-panel-title">
            <span className="lineup-title-default">Alineación</span>
            <span className="lineup-title-result">Resultado</span>
            <div className="teams-panel-actions">
              <strong>{matchKinds[activeKind].teamSize}v{matchKinds[activeKind].teamSize}</strong>
            </div>
          </div>
          <div className="balance-summary" title={balanceSummary.detail}>
            <div>
              <span>Equilibrio de equipos</span>
              <strong>{balanceSummary.percent > 0 ? `${balanceSummary.percent}%` : "Pendiente"}</strong>
            </div>
            <i aria-hidden="true">
              <b style={{ width: `${balanceSummary.percent}%` }} />
            </i>
            <small>{balanceSummary.label} · {balanceSummary.detail}</small>
          </div>
          <MatchPitch
            teamA={suggested.teamA}
            teamB={suggested.teamB}
            lineupSlots={activeMatch.lineupSlots}
            balanceSummary={balanceSummary}
            kind={activeKind}
            orientation={activeMatchManagerPane === "alineacion" ? "landscape" : "portrait"}
            scoreForPlayer={effectivePlayerScore}
            boardState={pitchBoardState}
            canDragPlayers={canEditLineup && registrationOpen && !lineupClosed && !matchFinalized}
            canUseBoard={!matchFinalized}
            onBoardStateChange={setPitchBoardState}
            onPlayerSwap={swapLineupPlayers}
            onZoom={openPitchZoom}
          />
          <div className={lineupClosed ? "lineup-state closed" : "lineup-state"}>
            {!matchConfigured ? "Alineación pendiente" : lineupClosed ? "Alineación cerrada" : "Alineación abierta"}
          </div>
          <div className="lineup-actions">
            <button type="button" onClick={applyRandomTeams} disabled={!canEditLineup}>Aleatorio</button>
            <button type="button" onClick={applyBalancedTeams} disabled={!canEditLineup}>Equilibrado</button>
          </div>
          <Team title="Equipo 1" players={suggested.teamA} variant="team-a" scoreForPlayer={effectivePlayerScore} mediaForPlayer={playerMediaScore} formForPlayer={playerForm} />
          <Team title="Equipo 2" players={suggested.teamB} variant="team-b" scoreForPlayer={effectivePlayerScore} mediaForPlayer={playerMediaScore} formForPlayer={playerForm} />
          {canUseAdminControls && matchConfigured && !matchFinalized ? (
            <button className="primary-button full" onClick={() => void toggleLineupClosed()}>
              {lineupClosed ? "Abrir alineación" : "Cerrar alineación"}
            </button>
          ) : null}
          <div className="result-box">
            <span>Resultado</span>
            <div className="result-score-grid">
              <label className="result-score-field team-a-score">
                <span>Equipo 1</span>
                <input
                  aria-label="Resultado equipo 1"
                  type="number"
                  min="0"
                  value={result.a}
                  disabled={!matchConfigured || matchFinalized}
                  onChange={(event) => setResult({ ...result, a: event.target.value })}
                  inputMode="numeric"
                />
              </label>
              <b>-</b>
              <label className="result-score-field team-b-score">
                <span>Equipo 2</span>
                <input
                  aria-label="Resultado equipo 2"
                  type="number"
                  min="0"
                  value={result.b}
                  disabled={!matchConfigured || matchFinalized}
                  onChange={(event) => setResult({ ...result, b: event.target.value })}
                  inputMode="numeric"
                />
              </label>
            </div>
            <div className={activeMatch.teamPhoto ? "team-photo-card has-photo" : "team-photo-card"}>
              {activeMatch.teamPhoto ? (
                <button
                  className="team-photo-preview-button"
                  type="button"
                  onClick={() => setMatchPhotoPreview({ src: activeMatch.teamPhoto!, title: activeMatch.title })}
                  aria-label={`Ver foto del partido ${activeMatch.title}`}
                >
                  <img src={activeMatch.teamPhoto} alt={`Foto del partido ${activeMatch.title}`} />
                  <span>Ver foto</span>
                </button>
              ) : (
                <span className="team-photo-empty">+</span>
              )}
              {!matchFinalized ? (
                <div className="team-photo-actions">
                  <label className="team-photo-button">
                    {activeMatch.teamPhoto ? "Cambiar foto del partido" : "Añadir foto del partido"}
                    <input
                      accept="image/*"
                      capture="environment"
                      disabled={!canUploadTeamPhoto}
                      onChange={(event) => {
                        void uploadTeamPhoto(event.target.files?.[0]);
                        event.currentTarget.value = "";
                      }}
                      type="file"
                    />
                  </label>
                  {canUseAdminControls && activeMatch.teamPhoto ? (
                    <button className="team-photo-remove" type="button" onClick={removeTeamPhoto}>
                      Quitar foto
                    </button>
                  ) : null}
                </div>
              ) : null}
              {!matchFinalized && teamPhotoMessage ? <small className="team-photo-message">{teamPhotoMessage}</small> : null}
            </div>
            <div className="scorers-box">
              <strong>Goles</strong>
              {!matchConfigured ? <small>Guarda primero el partido.</small> : null}
              {matchConfigured && !matchFinalized && !lineupClosed ? <small>Cierra la alineación para calcular pago y finalizar.</small> : null}
              {matchConfigured && confirmedPlayers.length === 0 ? <small>Marca asistentes para añadir goleadores.</small> : null}
              {confirmedPlayers.length > 0 && !resultIsReady ? <small>Rellena primero el resultado.</small> : null}
              {matchConfigured && confirmedPlayers.length > 0 && resultIsReady ? (
                <div className="scorers-teams">
                  <div className="scorers-team team-a-scorers">
                    <div className="scorers-team-title">
                      <span>Equipo 1</span>
                      <b>{scoreAValue}</b>
                    </div>
                    {scorerRows(suggested.teamA, "team-a")}
                  </div>
                  <div className="scorers-team team-b-scorers">
                    <div className="scorers-team-title">
                      <span>Equipo 2</span>
                      <b>{scoreBValue}</b>
                    </div>
                    {scorerRows(suggested.teamB, "team-b")}
                  </div>
                </div>
              ) : null}
            </div>
            {matchFinalized ? (
              null
            ) : (
              <button disabled={!matchConfigured || !lineupClosed || !resultIsReady || !canUseAdminControls} onClick={() => void finalizeMatch()}>Finalizar partido</button>
            )}
          </div>
          {matchFinalized && canUseAdminControls && ratingsEnabled && supabase && remoteGroupId ? (
            <GlobalRatingPanel
              client={supabase}
              clientMetadata={clientOperationMetadata}
              expectedRevision={remotePayloadRevision}
              groupId={remoteGroupId}
              matchId={activeMatch.id}
              onCommit={(commit) => applyRemoteCommit(commit as RemotePayloadCommit)}
            />
          ) : null}
        </aside>
      </section>

      {matchPhotoPreview ? (
        <div
          className="match-photo-preview-backdrop"
          role="presentation"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) setMatchPhotoPreview(null);
          }}
        >
          <section className="match-photo-preview-dialog" role="dialog" aria-modal="true" aria-label={`Foto del partido ${matchPhotoPreview.title}`}>
            <div className="match-photo-preview-title">
              <strong>{matchPhotoPreview.title}</strong>
              <button type="button" onClick={() => setMatchPhotoPreview(null)}>Cerrar</button>
            </div>
            <img src={matchPhotoPreview.src} alt={`Foto del partido ${matchPhotoPreview.title}`} />
          </section>
        </div>
      ) : null}

      {pitchZoomOpen ? (
        <div
          className={`pitch-modal-backdrop ${activeMatchManagerPane === "alineacion" ? "pitch-modal-fullscreen-backdrop" : ""}`.trim()}
          role="presentation"
        >
          <section
            className={`pitch-modal ${activeMatchManagerPane === "alineacion" ? "pitch-modal-fullscreen" : ""}`.trim()}
            role="dialog"
            aria-modal="true"
            aria-labelledby="pitch-modal-title"
            style={{ justifyItems: "stretch" }}
          >
            <div className="pitch-modal-title">
              <div>
                <span>Campo en grande</span>
                <strong id="pitch-modal-title">{matchKinds[activeKind].teamSize}v{matchKinds[activeKind].teamSize}</strong>
              </div>
              <button type="button" onClick={closePitchZoom}>Cerrar</button>
            </div>
            <div className="pitch-modal-pitch-wrap">
              <MatchPitch
                className="match-pitch-zoomed"
                teamA={suggested.teamA}
                teamB={suggested.teamB}
                lineupSlots={activeMatch.lineupSlots}
                balanceSummary={balanceSummary}
                kind={activeKind}
                orientation={activeMatchManagerPane === "alineacion" ? "landscape" : "portrait"}
                scoreForPlayer={effectivePlayerScore}
                boardState={pitchBoardState}
                canDragPlayers={canEditLineup && registrationOpen && !lineupClosed && !matchFinalized}
                canUseBoard={!matchFinalized}
                onBoardStateChange={setPitchBoardState}
                onPlayerSwap={swapLineupPlayers}
              />
            </div>
          </section>
        </div>
      ) : null}

      {teamGalleryOpen ? (
        <section className="panel team-gallery-panel" id="mi-equipo" ref={teamGalleryRef}>
          <div className="panel-title">
            <span>Mi equipo</span>
            <div className="team-gallery-title-actions">
              <strong>{teamGalleryPlayers.length}</strong>
              <button type="button" onClick={() => setTeamGalleryOpen(false)}>Cerrar</button>
            </div>
          </div>
          {teamGalleryPlayers.length > 0 ? (
            <div className="team-card-gallery">
              {teamGalleryPlayers.map((player) => renderTeamMiniCard(player))}
            </div>
          ) : (
            <p className="empty-copy">Todavía no hay fichas de jugadores en este equipo.</p>
          )}
        </section>
      ) : null}

      <section className={`${selectedPlayer ? "bottom-grid" : "bottom-grid without-profile"} ${sharedLinkContentBlocked ? "gated-shell" : ""}`} data-profile-pane={profilePane}>
        {selectedPlayer ? (
          <div className={`panel player-profile ${playerProfileMode === "viewer" ? "profile-viewer" : "profile-editor"}`} ref={playerProfileRef}>
            <div className="panel-title">
              <span>{playerProfileMode === "viewer" ? "Ficha de jugador" : "Mi perfil"}</span>
              <div className="profile-title-actions">
                {selectedPlayerIsOwn ? <small className="own-label">Tu ficha universal</small> : null}
                {selectedPlayer.inactive ? <small className="inactive-label">Ya no está</small> : null}
                {isDemoMode ? (
                  <button className="profile-return-button" type="button" onClick={returnFromPlayerProfile}>
                    Volver
                  </button>
                ) : null}
                {playerProfileMode === "edit" && canUseAdminControls && !selectedPlayer.inactive ? (
                  <button
                    className="trash-icon-button profile-delete-button"
                    onClick={() => deactivatePlayer(selectedPlayer.id)}
                    title="Eliminar jugador"
                    type="button"
                    aria-label="Eliminar jugador"
                  >
                    <TrashLogo />
                  </button>
                ) : null}
                <button className="profile-close-button" type="button" onClick={closePlayerProfile}>
                  Cerrar
                </button>
                <strong>{overallScore(selectedPeerScore)}</strong>
              </div>
            </div>
            {playerProfileMode === "edit" && selectedPlayerIsOwn && hasRealTeam ? (
              <details className="player-profile-group-details">
                <summary>
                  <span>Datos del grupo</span>
                  <small>{currentTeamName}</small>
                  <b aria-hidden="true">›</b>
                </summary>
                <dl>
                  <div><dt>Código</dt><dd>{currentTeam?.teamCode ?? "-"}</dd></div>
                  <div><dt>Rol</dt><dd>{memberRoleLabel(displayedRole)}</dd></div>
                  <div><dt>Nivel</dt><dd>{groupLevel === null ? "-" : overallScore(groupLevel)}</dd></div>
                </dl>
              </details>
            ) : null}
            {playerProfileMode === "edit" && selectedPlayerIsOwn ? (
              <>
                <a className="profile-notifications-link" href="/perfil/avisos">
                  <span>Avisos y notificaciones</span>
                  <small>Preferencias por categoría y canal</small>
                  <b aria-hidden="true">›</b>
                </a>
                <a className="profile-notifications-link" href="/perfil/conducta">
                  <span>Avisos y conducta</span>
                  <small>Asistencia, medidas y apelaciones</small>
                  <b aria-hidden="true">›</b>
                </a>
                <a className="profile-notifications-link" href="/personalizar-carta">
                  <span>Personalizar ficha</span>
                  <small>Tu colección, efectos y logro destacado</small>
                  <b aria-hidden="true">›</b>
                </a>
              </>
            ) : null}
            {!ownPlayer && selectedPlayer && !selectedPlayer.ownerUserId && hasRealTeam && isRegisteredUser ? (
              <div className="profile-claim">
                <span>¿Esta ficha eres tú?</span>
                <button type="button" onClick={() => void claimSelectedPlayer()}>Esta es mi ficha</button>
              </div>
            ) : null}
            {playerProfileMode === "viewer" ? (
              <div className="player-profile-viewer">
                <div className="player-profile-viewer-card">
                  {renderSelectedPlayerCard(false)}
                </div>
                <div className="player-profile-viewer-details">
                  <div className="player-public-stats" aria-label={`Resumen de ${playerDisplayName(selectedPlayer)}`}>
                    <div>
                      <span>Posición</span>
                      <strong>{positionShort(selectedPlayer)}</strong>
                    </div>
                    <div>
                      <span>Partidos</span>
                      <strong>{selectedPlayer.appearances}</strong>
                    </div>
                    <div>
                      <span>Goles</span>
                      <strong>{selectedPlayer.goals}</strong>
                    </div>
                    <div>
                      <span>Edad</span>
                      <strong>{selectedPlayerAge !== null ? selectedPlayerAge : "-"}</strong>
                    </div>
                  </div>
                  {renderSelectedPlayerRatingPanel()}
                </div>
              </div>
            ) : (
            <>
              <div className="profile-top">
                {renderSelectedPlayerCard(true)}
                <div>
                  {showPlayerSwitcher ? (
                    <label className="profile-player-switcher">
                      Cambiar ficha
                      <select
                        value={selectedPlayer.id}
                        onChange={(event) => {
                          setProfilePane("ficha");
                          setSelectedPlayerId(event.target.value);
                        }}
                      >
                        {players.map((player) => (
                          <option key={player.id} value={player.id}>{playerDisplayName(player)}</option>
                        ))}
                      </select>
                    </label>
                  ) : null}
                  <input
                    value={selectedPlayer.name}
                    disabled={!canEditSelectedPlayer}
                    onBlur={() => updatePlayer(selectedPlayer.id, { name: displayName(selectedPlayer.name) })}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { name: event.target.value })}
                  />
                  <input
                    inputMode="tel"
                    placeholder="Teléfono Bizum"
                    value={selectedPlayer.phone ?? ""}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { phone: event.target.value })}
                  />
                  <div className="birthdate-row">
                    <label>
                      Fecha nacimiento
                      <input
                        type="date"
                        max={currentDateValue}
                        value={selectedPlayer.birthDate ?? ""}
                        disabled={!canEditSelectedPlayer}
                        onKeyDown={(event) => {
                          if (event.key === "Enter" || event.key === " " || event.key === "ArrowDown") {
                            requestNativeInputPicker(event.currentTarget);
                          }
                        }}
                        onPointerDown={(event) => {
                          if (event.button === 0) requestNativeInputPicker(event.currentTarget);
                        }}
                        onChange={(event) => updatePlayer(selectedPlayer.id, { birthDate: normalizeBirthDate(event.target.value) || undefined })}
                      />
                    </label>
                    <div className="age-pill" aria-label="Edad calculada">
                      <span>Edad</span>
                      <strong>{selectedPlayerAge !== null ? `${selectedPlayerAge}` : "-"}</strong>
                      <small>{selectedPlayerAge !== null ? "años" : "pendiente"}</small>
                    </div>
                  </div>
                  <label className="profile-position-row">
                    <span>Posición preferida</span>
                    <select
                      value={selectablePositionValue(selectedPlayer.position)}
                      disabled={!canEditSelectedPlayer}
                      onChange={(event) => {
                        const position = event.target.value as PlayerPosition;
                        updatePlayer(selectedPlayer.id, {
                          position,
                          ...(isGoalkeeperPosition(position) ? {} : { outfieldPosition: position }),
                        });
                      }}
                    >
                      {allPositionOptions.map((option) => (
                        <option key={option.value} value={option.value}>{option.value}</option>
                      ))}
                    </select>
                  </label>
                  <div className="profile-save-area">
                    <button
                      className="profile-save-button"
                      type="button"
                      onClick={() => void saveSelectedPlayerProfile()}
                      disabled={!canEditSelectedPlayer || profileSaving}
                    >
                      {profileSaving ? "Guardando..." : "Guardar ficha"}
                    </button>
                    {profileSaveMessage ? <small className="profile-save-message">{profileSaveMessage}</small> : null}
                    <ThemeToggle />
                  </div>
                </div>
              </div>
              <div className="profile-fields">
                <label className="toggle-field">
                  <input
                    type="checkbox"
                    checked={Boolean(selectedPlayer.goalkeeperOnly)}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => {
                      const goalkeeperOnly = event.target.checked;
                      const outfieldPosition = rememberedOutfieldPosition(selectedPlayer, activeKind);
                      updatePlayer(selectedPlayer.id, {
                        goalkeeperOnly,
                        outfieldPosition,
                        position: goalkeeperOnly ? "Portero" : outfieldPosition,
                      });
                    }}
                  />
                  Portero fijo
                </label>
                <label className="toggle-field injured-toggle">
                  <input
                    type="checkbox"
                    checked={Boolean(selectedPlayer.injured)}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => setPlayerInjured(selectedPlayer.id, event.target.checked)}
                  />
                  Lesionado
                </label>
                {selectedPlayerIsOwn ? (
                  <div className="market-profile-box">
                    <label className="toggle-field market-toggle">
                      <input
                        type="checkbox"
                        checked={Boolean(selectedPlayer.marketEnabled)}
                        disabled={!canEditSelectedPlayer}
                        onChange={(event) => updatePlayer(selectedPlayer.id, { marketEnabled: event.target.checked })}
                      />
                      Mostrarme en mercado de fichajes
                    </label>
                    <div className="market-profile-fields">
                      <div className="market-zone-field">
                        <label>
                          Zonas donde puedes jugar
                          <span className="market-zone-picker">
                            <span className="market-zone-control">
                              <small>Ciudad</small>
                              <input
                                ref={marketZoneInputRef}
                                placeholder="Busca una ciudad con Google Places"
                                value={marketZoneDraft}
                                disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                                onChange={(event) => setMarketZoneDraft(event.target.value)}
                              />
                            </span>
                            <span className="market-zone-control">
                              <small>Distancia máxima</small>
                              <select
                                aria-label="Radio de desplazamiento para la próxima zona"
                                value={marketZoneRadiusKm}
                                disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                                onChange={(event) => setMarketZoneRadiusKm(normalizeMarketZoneRadius(event.target.value))}
                              >
                                {marketZoneRadiusOptions.map((option) => (
                                  <option key={option.value} value={option.value}>
                                    {option.label}
                                  </option>
                                ))}
                              </select>
                            </span>
                          </span>
                        </label>
                        <div className="market-zone-chips">
                          {selectedMarketZones.length ? (
                            selectedMarketZones.map((zone) => (
                              <div className="market-zone-chip" key={zone.placeId}>
                                <span>{marketZoneLabelFromPlace(zone)}</span>
                                <select
                                  aria-label={`Radio para ${marketZoneLabelFromPlace(zone)}`}
                                  value={zone.radiusKm}
                                  disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                                  onChange={(event) => {
                                    const nextZones = updateMarketZoneRadius(selectedPlayer.marketZonesGeo, zone.placeId, Number(event.target.value));
                                    updatePlayer(selectedPlayer.id, {
                                      marketZones: marketZoneTextFromGeo(nextZones),
                                      marketZonesGeo: nextZones,
                                    });
                                  }}
                                >
                                  {marketZoneRadiusOptions.map((option) => (
                                    <option key={option.value} value={option.value}>
                                      {option.label}
                                    </option>
                                  ))}
                                </select>
                                <button
                                  type="button"
                                  aria-label={`Quitar ${marketZoneLabelFromPlace(zone)}`}
                                  disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                                  onClick={() => {
                                    const nextZones = removeMarketZoneGeo(selectedPlayer.marketZonesGeo, zone.placeId);
                                    updatePlayer(selectedPlayer.id, {
                                      marketZones: marketZoneTextFromGeo(nextZones),
                                      marketZonesGeo: nextZones,
                                    });
                                  }}
                                >
                                  ×
                                </button>
                              </div>
                            ))
                          ) : (
                            <small>Añade al menos una ciudad.</small>
                          )}
                        </div>
                        {marketZonePlaceStatus === "missing-key" ? <small className="market-field-warning">Google Places pendiente.</small> : null}
                        {marketZonePlaceMessage ? <small className="market-field-warning">{marketZonePlaceMessage}</small> : null}
                      </div>
                      <div className="market-availability-builder">
                        <span>Disponibilidad</span>
                        <div>
                          {selectedMarketAvailabilitySlots.map((slot) => (
                            <div className={slot.enabled ? "market-day-row active" : "market-day-row"} key={slot.dayKey}>
                              <label>
                                <input
                                  type="checkbox"
                                  checked={slot.enabled}
                                  disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                                  onChange={(event) => {
                                    updatePlayer(selectedPlayer.id, {
                                      marketAvailability: updateMarketAvailabilityText(selectedPlayer.marketAvailability, slot.dayKey, { enabled: event.target.checked }),
                                    });
                                  }}
                                />
                                {slot.label}
                              </label>
                              <select
                                value={slot.start}
                                disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled || !slot.enabled}
                                onChange={(event) => {
                                  updatePlayer(selectedPlayer.id, {
                                    marketAvailability: updateMarketAvailabilityText(selectedPlayer.marketAvailability, slot.dayKey, { start: event.target.value }),
                                  });
                                }}
                              >
                                {marketTimeOptions.map((time) => (
                                  <option key={time} value={time}>{time}</option>
                                ))}
                              </select>
                              <span>a</span>
                              <select
                                value={slot.end}
                                disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled || !slot.enabled}
                                onChange={(event) => {
                                  updatePlayer(selectedPlayer.id, {
                                    marketAvailability: updateMarketAvailabilityText(selectedPlayer.marketAvailability, slot.dayKey, { end: event.target.value }),
                                  });
                                }}
                              >
                                {marketTimeOptions.map((time) => (
                                  <option key={time} value={time}>{time}</option>
                                ))}
                              </select>
                            </div>
                          ))}
                        </div>
                      </div>
                      <div className="market-modality-options">
                        <span>Modalidades</span>
                        {Object.entries(matchKinds).map(([kind, config]) => {
                          const modality = kind as MatchKind;
                          const selectedModalities = marketModalitiesForPlayer(selectedPlayer);
                          return (
                            <label key={kind}>
                              <input
                                type="checkbox"
                                checked={selectedModalities.includes(modality)}
                                disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                                onChange={(event) => {
                                  const next = event.target.checked
                                    ? [...new Set([...selectedModalities, modality])]
                                    : selectedModalities.filter((item) => item !== modality);
                                  updatePlayer(selectedPlayer.id, { marketModalities: next.length ? next : [modality] });
                                }}
                              />
                              {config.label}
                            </label>
                          );
                        })}
                      </div>
                      <label className="market-bio-field">
                        Presentación
                        <textarea
                          placeholder="Portero puntual, me desplazo por la zona norte..."
                          value={selectedPlayer.marketBio ?? ""}
                          disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                          onChange={(event) => updatePlayer(selectedPlayer.id, { marketBio: event.target.value })}
                        />
                      </label>
                      <div className="market-intent-options">
                        <label>
                          <input
                            type="checkbox"
                            checked={selectedPlayer.marketOpenToGuest ?? true}
                            disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                            onChange={(event) => updatePlayer(selectedPlayer.id, { marketOpenToGuest: event.target.checked })}
                          />
                          Acepto invitaciones puntuales
                        </label>
                        <label>
                          <input
                            type="checkbox"
                            checked={selectedPlayer.marketOpenToGroup ?? true}
                            disabled={!canEditSelectedPlayer || !selectedPlayer.marketEnabled}
                            onChange={(event) => updatePlayer(selectedPlayer.id, { marketOpenToGroup: event.target.checked })}
                          />
                          Acepto entrar en grupos
                        </label>
                      </div>
                    </div>
                    <small>{selectedPlayer.marketEnabled && !selectedMarketReady ? "Para publicarte, añade al menos una zona y un horario activo." : "Se publica solo si guardas la ficha con esta opción marcada. Tu historial del grupo no se comparte."}</small>
                  </div>
                ) : null}
                {renderSelectedPlayerRatingPanel()}
                <label>
                  Goles
                  <input
                    type="number"
                    min="0"
                    value={selectedPlayer.goals}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { goals: Number(event.target.value) })}
                  />
                </label>
              </div>
            </>
            )}
          </div>
        ) : null}

        <div className="panel" id="ranking">
          <div className="panel-title">
            <span>Ranking</span>
            <strong>{rankedPlayers.length}</strong>
          </div>
          <div className="ranking-toolbar">
            <label className="ranking-season-filter">
              Temporada
              <select value={activeRankingSeason} onChange={(event) => setRankingSeason(event.target.value)}>
                {rankingSeasons.map((season) => (
                  <option key={season} value={season}>{season}</option>
                ))}
              </select>
            </label>
            <div className="ranking-sort-filter">
              <span>Ordenar por</span>
              <div className="ranking-sort-buttons">
                {(Object.keys(rankingSortLabels) as RankingSort[]).map((sort) => (
                  <button
                    className={rankingSort === sort ? "selected" : ""}
                    key={sort}
                    onClick={() => setRankingSort(sort)}
                    type="button"
                  >
                    {rankingSortLabels[sort]}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <div className="ranking ranking-card-grid">
            {rankedPlayers.map((row, index) => renderRankingMiniCard(row, index))}
          </div>
        </div>
      </section>
      {statusConfirmation ? (
        <div
          className="status-confirm-backdrop"
          role="presentation"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) closeStatusConfirmation();
          }}
        >
          <section
            className="status-confirm-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="status-confirm-title"
            aria-describedby="status-confirm-copy"
          >
            <span>Movimiento de plaza</span>
            <h2 id="status-confirm-title">¿Cambiar asistencia?</h2>
            <p id="status-confirm-copy">
              Si {statusConfirmationPlayerName} deja de ir, perderá su posición. Si hay reservas, el primero ocupará su plaza.
            </p>
            <div className="status-confirm-summary">
              <small>Nuevo estado</small>
              <strong>{statusConfirmationTargetLabel}</strong>
            </div>
            <div className="status-confirm-actions">
              <button className="status-confirm-cancel" type="button" onClick={closeStatusConfirmation}>
                Mantener plaza
              </button>
              <button className="status-confirm-accept" type="button" onClick={confirmStatusChange}>
                {statusConfirmationActionLabel}
              </button>
            </div>
          </section>
        </div>
      ) : null}
      {!needsLoginForSharedLink && mobileAccountOpen ? (
        <>
          <button
            className="mobile-account-backdrop"
            type="button"
            aria-label="Cerrar menú de perfil"
            onClick={() => setMobileAccountOpen(false)}
          />
          <section className="mobile-account-sheet" role="dialog" aria-modal="true" aria-label="Perfil y ajustes">
            <header className="mobile-account-header">
              <span className="mobile-account-avatar" aria-hidden="true">
                {nameInitials(profileName || authDisplayName(authUser))}
              </span>
              <span className="mobile-account-identity">
                <strong>{displayName(profileName || authDisplayName(authUser)) || "Jugador"}</strong>
                <small>
                  {hasRealTeam ? `${currentTeamName} · ${memberRoleLabel(displayedRole)}` : "Sin grupo de pachangas"}
                </small>
              </span>
              <button
                className="mobile-account-close"
                type="button"
                aria-label="Cerrar menú de perfil"
                onClick={() => setMobileAccountOpen(false)}
              >
                ×
              </button>
            </header>
            <div className="mobile-account-scroll">
              <div className="mobile-account-group">
                <h2>Jugador</h2>
                <button
                  type="button"
                  onClick={() => runMobileAccountAction(() => void openOwnPlayerProfile())}
                  disabled={!hasRealTeam || !isRegisteredUser}
                >
                  <span>Mi ficha</span><small>Datos, posición, forma y valoraciones</small><b aria-hidden="true">›</b>
                </button>
                <a href="/perfil/avisos">
                  <span>Avisos y notificaciones</span><small>Elige categorías y canales</small><b aria-hidden="true">›</b>
                </a>
                <a href="/perfil/conducta">
                  <span>Avisos y conducta</span><small>Asistencia, medidas y apelaciones</small><b aria-hidden="true">›</b>
                </a>
                <button type="button" onClick={() => runMobileAccountAction(openTeamGallery)} disabled={!hasRealTeam}>
                  <span>Equipo</span><small>Ranking del grupo con filtros</small><b aria-hidden="true">›</b>
                </button>
                <button
                  type="button"
                  onClick={() => runMobileAccountAction(openRankingPanel)}
                >
                  <span>Ranking</span><small>Media, goles, partidos y victorias</small><b aria-hidden="true">›</b>
                </button>
                <a href="/mercado">
                  <span>Mercado</span><small>Jugadores disponibles y partidos abiertos</small><b aria-hidden="true">›</b>
                </a>
              </div>

              <div className="mobile-account-group">
                <h2>Mi grupo</h2>
                {hasRealTeam ? (
                  <details className="mobile-account-group-details">
                    <summary>
                      <span>Datos del grupo</span>
                      <small>Código, rol y nivel</small>
                      <b aria-hidden="true">›</b>
                    </summary>
                    <dl>
                      <div><dt>Grupo</dt><dd>{currentTeamName}</dd></div>
                      <div><dt>Código</dt><dd>{currentTeam?.teamCode ?? "-"}</dd></div>
                      <div><dt>Rol</dt><dd>{memberRoleLabel(displayedRole)}</dd></div>
                      <div><dt>Nivel</dt><dd>{groupLevel === null ? "-" : overallScore(groupLevel)}</dd></div>
                    </dl>
                  </details>
                ) : null}
                {hasRealTeam ? (
                  <a href={`/equipo/identidad${remoteGroupId ? `?grupo=${remoteGroupId}` : ""}`}>
                    <span>Escudo, logros y colección</span><small>Identidad oficial y recompensas del equipo</small><b aria-hidden="true">›</b>
                  </a>
                ) : null}
                <button type="button" onClick={() => runMobileAccountAction(openGroupSwitcher)} disabled={!isRegisteredUser}>
                  <span>Cambiar de pachanga</span><small>Entra en otro de tus grupos</small><b aria-hidden="true">›</b>
                </button>
                {hasRealTeam ? (
                  <button
                    className="danger"
                    type="button"
                    onClick={() => runMobileAccountAction(() => void leaveCurrentTeam())}
                    disabled={currentRole === "owner"}
                  >
                    <span>Abandonar equipo</span>
                    <small>{currentRole === "owner" ? "Transfiere antes la propiedad en Configuración" : "Conserva tu ficha, Rating e historial"}</small>
                    <b aria-hidden="true">›</b>
                  </button>
                ) : null}
                <a href="/manual">
                  <span>Manual de usuario</span><small>Flujos para jugadores y administradores</small><b aria-hidden="true">›</b>
                </a>
              </div>

              {canUseAdminControls || canCreateTeam ? (
                <div className="mobile-account-group">
                  <h2>Administrar</h2>
                  <button type="button" onClick={() => runMobileAccountAction(createMatch)} disabled={!canUseAdminControls}>
                    <span>Crear partido</span><small>Fecha, campo, modalidad y plazas</small><b aria-hidden="true">›</b>
                  </button>
                  <button
                    type="button"
                    onClick={() => runMobileAccountAction(() => void openCreatePlayerProfile())}
                    disabled={!canUseAdminControls && (!hasRealTeam || !isRegisteredUser)}
                  >
                    <span>Crear ficha de jugador</span><small>Añade un miembro al grupo</small><b aria-hidden="true">›</b>
                  </button>
                  <button
                    type="button"
                    onClick={() => runMobileAccountAction(() => showQuickForm("venue"))}
                    disabled={!canUseAdminControls}
                  >
                    <span>Crear campo</span><small>Dirección, precio y modalidad</small><b aria-hidden="true">›</b>
                  </button>
                  <button type="button" onClick={() => runMobileAccountAction(() => showQuickForm("team"))}>
                    <span>{isDemoMode ? "Crear mi grupo limpio" : "Crear grupo de pachangas"}</span>
                    <small>{isDemoMode ? "Salir de la demo y empezar desde cero" : "Empieza un grupo nuevo"}</small>
                    <b aria-hidden="true">›</b>
                  </button>
                  {canUseAdminControls ? (
                    <>
                      <button type="button" onClick={() => runMobileAccountAction(() => setRewardBoxDemoOpen(true))}>
                        <span>Animación de logro</span><small>Prueba visual de la recompensa</small><b aria-hidden="true">›</b>
                      </button>
                      <button type="button" onClick={() => runMobileAccountAction(toggleSettingsPanel)}>
                        <span>Configuración</span><small>Colores, roles, suscripción y copias</small><b aria-hidden="true">›</b>
                      </button>
                    </>
                  ) : null}
                </div>
              ) : null}

              <div className="mobile-account-group">
                <h2>Información</h2>
                <a href="/condiciones"><span>Condiciones de uso</span><b aria-hidden="true">›</b></a>
                <a href="/privacidad"><span>Privacidad</span><b aria-hidden="true">›</b></a>
                <a href="/cookies"><span>Cookies</span><b aria-hidden="true">›</b></a>
                <a href="/aviso-legal"><span>Aviso legal</span><b aria-hidden="true">›</b></a>
              </div>

              {isRegisteredUser ? (
                <button className="mobile-account-session danger" type="button" onClick={() => void signOut()}>
                  Cerrar sesión
                </button>
              ) : (
                <button
                  className="mobile-account-session"
                  type="button"
                  onClick={() => runMobileAccountAction(() => void signInWithGoogle())}
                >
                  <GoogleLogo /> Continuar con Google
                </button>
              )}
            </div>
          </section>
        </>
      ) : null}
      {!needsLoginForSharedLink ? (
        <MobileAppNav
          active={activeMobileTab}
          adminViewPreview={canPreviewPlayerView ? { active: playerPreviewActive, onToggle: toggleAdminPlayerView } : undefined}
          onNavigate={navigatePrimaryMobile}
        />
      ) : null}
      <RewardBoxDemo open={rewardBoxDemoOpen && canUseAdminControls} onClose={() => setRewardBoxDemoOpen(false)} />
    </main>
  );
}

function Team({
  title,
  formForPlayer = () => ({
    balanceScore: 5,
    hasData: false,
    label: "Normal",
    notes: [],
    percent: 100,
    recentAverage: null,
    reliability: 100,
    status: "normal",
  }),
  mediaForPlayer = scorePlayer,
  players,
  scoreForPlayer = scorePlayer,
  variant,
}: {
  title: string;
  formForPlayer?: (player: Player) => PlayerFormState;
  mediaForPlayer?: PlayerScoreFn;
  players: Player[];
  scoreForPlayer?: PlayerScoreFn;
  variant: "team-a" | "team-b";
}) {
  const orderedPlayers = sortedLineupPlayers(players, scoreForPlayer);

  return (
    <div className={`team ${variant}`}>
      <h2>{title}</h2>
      {players.length === 0 ? <p>Marca jugadores como “Voy”.</p> : null}
      {orderedPlayers.map((player) => {
        const formState = formForPlayer(player);

        return (
          <div className={`team-player-row ${playerPosition(player) === "Porteria" ? "goalkeeper-row" : ""}`} key={player.id}>
            <span className="team-player-main">
              {player.inactive ? (
                <span className="inline-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                  <UserOffLogo />
                </span>
              ) : null}
              {player.injured ? (
                <span className="inline-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                  <HospitalLogo />
                </span>
              ) : null}
              <b className="team-player-name">{playerDisplayName(player)}</b>
              <em className="team-player-meta">
                ({overallScore(mediaForPlayer(player))}){formState.hasData ? ` · Forma ${visibleFormPercent(formState)}%` : ""} · {player.goals} G
              </em>
            </span>
            <small className="position-pill" title={positionLabel(player)} aria-label={positionLabel(player)}>
              {positionShort(player)}
            </small>
          </div>
        );
      })}
    </div>
  );
}

type PitchDragState = {
  dx: number;
  dy: number;
  sourceId: string;
  targetId: string | null;
};

type PitchBoardInteraction =
  | { kind: "draw"; lineId: string; pointerId: number }
  | { grabOffsetX: number; grabOffsetY: number; kind: "player"; playerId: string; pointerId: number };

type PitchPointerState = {
  active: boolean;
  pointerId: number;
  sourceId: string;
  startX: number;
  startY: number;
};

type PitchOrientation = "landscape" | "portrait";

function MatchPitch({
  className = "",
  teamA,
  teamB,
  lineupSlots,
  balanceSummary,
  kind,
  orientation = "portrait",
  scoreForPlayer = scorePlayer,
  boardState = initialPitchBoardState(),
  canDragPlayers = false,
  canUseBoard: canUseBoardProp = true,
  onBoardStateChange,
  onPlayerSwap,
  onZoom,
}: {
  className?: string;
  teamA: Player[];
  teamB: Player[];
  lineupSlots?: LineupSlots;
  balanceSummary?: TeamBalanceSummary;
  kind: MatchKind;
  orientation?: PitchOrientation;
  scoreForPlayer?: PlayerScoreFn;
  boardState?: PitchBoardState;
  canDragPlayers?: boolean;
  canUseBoard?: boolean;
  onBoardStateChange?: Dispatch<SetStateAction<PitchBoardState>>;
  onPlayerSwap?: (sourcePlayerId: string, targetPlayerId: string) => void;
  onZoom?: () => void;
}) {
  const holdTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const boardInteractionRef = useRef<PitchBoardInteraction | null>(null);
  const boardPointerAbortRef = useRef<AbortController | null>(null);
  const pitchRef = useRef<HTMLDivElement | null>(null);
  const pointerAbortRef = useRef<AbortController | null>(null);
  const pointerRef = useRef<PitchPointerState | null>(null);
  const dropTargetRef = useRef<string | null>(null);
  const [boardDraggingPlayerId, setBoardDraggingPlayerId] = useState<string | null>(null);
  const [dragState, setDragState] = useState<PitchDragState | null>(null);
  const isLandscapePitch = orientation === "landscape";
  const canUseBoard = canUseBoardProp && isLandscapePitch;
  const boardMode = canUseBoard && boardState.active;
  const boardPlayersVisible = boardState.playersVisible;
  const teamATokens = placeTeam(teamA, kind, isLandscapePitch ? "left" : "bottom", scoreForPlayer, lineupSlots?.teamA);
  const teamBTokens = placeTeam(teamB, kind, isLandscapePitch ? "right" : "top", scoreForPlayer, lineupSlots?.teamB);
  const emptySlots = [
    ...teamATokens.empty.map((slot) => ({ ...slot, side: "A" as const, variant: "team-a" as const })),
    ...teamBTokens.empty.map((slot) => ({ ...slot, side: "B" as const, variant: "team-b" as const })),
  ];
  const tokens = [
    ...teamATokens.players.map((token) => ({ ...token, variant: "team-a" as const })),
    ...teamBTokens.players.map((token) => ({ ...token, variant: "team-b" as const })),
  ];

  useEffect(() => {
    return () => {
      if (holdTimerRef.current) clearTimeout(holdTimerRef.current);
      pointerAbortRef.current?.abort();
      boardPointerAbortRef.current?.abort();
    };
  }, []);

  useEffect(() => {
    if (canUseBoard) return;
    clearBoardInteraction();
    onBoardStateChange?.(initialPitchBoardState());
  }, [canUseBoard, onBoardStateChange]);

  function baseBoardPositions() {
    return tokens.reduce<Record<string, PitchBoardPoint>>((current, token) => {
      current[token.player.id] = { x: token.x, y: token.y };
      return current;
    }, {});
  }

  function updateBoardState(updater: SetStateAction<PitchBoardState>) {
    onBoardStateChange?.(updater);
  }

  function clearBoardInteraction() {
    boardPointerAbortRef.current?.abort();
    boardPointerAbortRef.current = null;
    boardInteractionRef.current = null;
    setBoardDraggingPlayerId(null);
  }

  function resetBoardDraft() {
    clearBoardInteraction();
    updateBoardState((current) => ({
      ...current,
      active: true,
      lines: [],
      playerPositions: baseBoardPositions(),
      playersVisible: true,
    }));
  }

  function closeBoardMode() {
    clearBoardInteraction();
    updateBoardState((current) => ({
      ...current,
      active: false,
      lines: [],
      playerPositions: {},
      playersVisible: true,
    }));
  }

  function toggleBoardMode() {
    if (boardMode) {
      closeBoardMode();
      return;
    }

    clearPitchDrag();
    updateBoardState((current) => ({
      ...current,
      active: true,
      lines: current.lines,
      playerPositions: Object.keys(current.playerPositions).length > 0 ? current.playerPositions : baseBoardPositions(),
    }));
  }

  function selectBoardColor(color: PitchBoardColor) {
    updateBoardState((current) => ({
      ...current,
      active: true,
      color,
    }));
  }

  function toggleBoardPlayersVisible() {
    updateBoardState((current) => ({
      ...current,
      active: true,
      playersVisible: !current.playersVisible,
    }));
  }

  function boardPointFromClient(clientX: number, clientY: number) {
    const rect = pitchRef.current?.getBoundingClientRect();
    if (!rect) return null;
    return {
      x: Math.max(0, Math.min(100, ((clientX - rect.left) / Math.max(rect.width, 1)) * 100)),
      y: Math.max(0, Math.min(100, ((clientY - rect.top) / Math.max(rect.height, 1)) * 100)),
    };
  }

  function appendBoardPoint(lineId: string, point: PitchBoardPoint) {
    updateBoardState((current) => ({
      ...current,
      lines: current.lines.map((line) => {
        if (line.id !== lineId) return line;
        const lastPoint = line.points.at(-1);
        if (lastPoint && Math.hypot(point.x - lastPoint.x, point.y - lastPoint.y) < 0.35) return line;
        return { ...line, points: [...line.points, point] };
      }),
    }));
  }

  function moveBoardInteraction(event: PointerEvent) {
    const interaction = boardInteractionRef.current;
    if (!interaction || interaction.pointerId !== event.pointerId) return;
    const point = boardPointFromClient(event.clientX, event.clientY);
    if (!point) return;
    event.preventDefault();

    if (interaction.kind === "draw") {
      appendBoardPoint(interaction.lineId, point);
      return;
    }

    updateBoardState((current) => ({
      ...current,
      active: true,
      playerPositions: {
        ...current.playerPositions,
        [interaction.playerId]: {
          x: Math.max(0, Math.min(100, point.x + interaction.grabOffsetX)),
          y: Math.max(0, Math.min(100, point.y + interaction.grabOffsetY)),
        },
      },
    }));
  }

  function finishBoardInteraction(event: PointerEvent) {
    const interaction = boardInteractionRef.current;
    if (!interaction || interaction.pointerId !== event.pointerId) return;
    event.preventDefault();
    clearBoardInteraction();
  }

  function cancelBoardInteraction(event: PointerEvent) {
    const interaction = boardInteractionRef.current;
    if (!interaction || interaction.pointerId !== event.pointerId) return;
    clearBoardInteraction();
  }

  function startBoardWindowTracking() {
    boardPointerAbortRef.current = new AbortController();
    window.addEventListener("pointermove", moveBoardInteraction, { passive: false, signal: boardPointerAbortRef.current.signal });
    window.addEventListener("pointerup", finishBoardInteraction, { passive: false, signal: boardPointerAbortRef.current.signal });
    window.addEventListener("pointercancel", cancelBoardInteraction, { passive: false, signal: boardPointerAbortRef.current.signal });
  }

  function startBoardDrawing(event: ReactPointerEvent<HTMLDivElement>) {
    if (!boardMode || !event.isPrimary) return;
    const target = event.target as Element | null;
    if (target?.closest("button, .pitch-board-toolbar")) return;
    const point = boardPointFromClient(event.clientX, event.clientY);
    if (!point) return;
    event.preventDefault();
    event.stopPropagation();
    clearBoardInteraction();
    const lineId = `line-${Date.now()}-${event.pointerId}`;
    updateBoardState((current) => ({
      ...current,
      active: true,
      lines: [...current.lines, { color: current.color, id: lineId, points: [point] }],
    }));
    boardInteractionRef.current = { kind: "draw", lineId, pointerId: event.pointerId };
    startBoardWindowTracking();
  }

  function startBoardPlayerDrag(event: ReactPointerEvent<HTMLButtonElement>, playerId: string, fallbackPosition: PitchBoardPoint) {
    if (!boardMode || !event.isPrimary) {
      startPitchDrag(event, playerId);
      return;
    }

    const point = boardPointFromClient(event.clientX, event.clientY);
    if (!point) return;
    event.preventDefault();
    event.stopPropagation();
    clearPitchDrag();
    clearBoardInteraction();
    const currentPosition = boardState.playerPositions[playerId] ?? fallbackPosition;
    boardInteractionRef.current = {
      grabOffsetX: currentPosition.x - point.x,
      grabOffsetY: currentPosition.y - point.y,
      kind: "player",
      playerId,
      pointerId: event.pointerId,
    };
    setBoardDraggingPlayerId(playerId);
    startBoardWindowTracking();
  }

  function clearPitchDrag() {
    if (holdTimerRef.current) clearTimeout(holdTimerRef.current);
    holdTimerRef.current = null;
    pointerAbortRef.current?.abort();
    pointerAbortRef.current = null;
    pointerRef.current = null;
    dropTargetRef.current = null;
    setDragState(null);
  }

  function nearestPitchDropTarget(clientX: number, clientY: number, sourceId: string) {
    const pitch = pitchRef.current;
    if (!pitch) return null;
    let bestDistance = Infinity;
    let bestId: string | null = null;

    pitch.querySelectorAll<HTMLElement>("[data-pitch-drop-id]").forEach((element) => {
      const targetId = element.dataset.pitchDropId;
      if (!targetId || targetId === `player:${sourceId}`) return;
      const rect = element.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      const distance = Math.hypot(clientX - centerX, clientY - centerY);
      const limit = Math.max(rect.width, rect.height) * 1.15;
      if (distance > limit) return;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestId = targetId;
      }
    });

    return bestId;
  }

  function activatePitchDrag(pointer: PitchPointerState, clientX: number, clientY: number) {
    if (holdTimerRef.current) clearTimeout(holdTimerRef.current);
    holdTimerRef.current = null;
    pointer.active = true;
    const targetId = nearestPitchDropTarget(clientX, clientY, pointer.sourceId);
    dropTargetRef.current = targetId;
    setDragState({
      dx: clientX - pointer.startX,
      dy: clientY - pointer.startY,
      sourceId: pointer.sourceId,
      targetId,
    });
  }

  function moveWindowPitchDrag(event: PointerEvent) {
    const pointer = pointerRef.current;
    if (!pointer || pointer.pointerId !== event.pointerId) return;
    const dx = event.clientX - pointer.startX;
    const dy = event.clientY - pointer.startY;

    if (!pointer.active) {
      if (!canDragPlayers || Math.hypot(dx, dy) < 10) return;
      activatePitchDrag(pointer, event.clientX, event.clientY);
    }

    event.preventDefault();
    const nextTargetId = nearestPitchDropTarget(event.clientX, event.clientY, pointer.sourceId);
    dropTargetRef.current = nextTargetId;
    setDragState({
      dx,
      dy,
      sourceId: pointer.sourceId,
      targetId: nextTargetId,
    });
  }

  function finishWindowPitchDrag(event: PointerEvent) {
    const pointer = pointerRef.current;
    if (!pointer || pointer.pointerId !== event.pointerId) return;

    const wasDragging = pointer.active;
    const sourceId = pointer.sourceId;
    const targetId = dropTargetRef.current ?? nearestPitchDropTarget(event.clientX, event.clientY, sourceId);
    clearPitchDrag();

    if (wasDragging) {
      event.preventDefault();
      if (targetId) onPlayerSwap?.(sourceId, targetId);
    }
  }

  function cancelWindowPitchDrag(event: PointerEvent) {
    const pointer = pointerRef.current;
    if (!pointer || pointer.pointerId !== event.pointerId) return;
    clearPitchDrag();
  }

  function startPitchDrag(event: ReactPointerEvent<HTMLButtonElement>, playerId: string) {
    if (!event.isPrimary) return;
    clearPitchDrag();
    pointerRef.current = {
      active: false,
      pointerId: event.pointerId,
      sourceId: playerId,
      startX: event.clientX,
      startY: event.clientY,
    };

    pointerAbortRef.current = new AbortController();
    window.addEventListener("pointermove", moveWindowPitchDrag, { passive: false, signal: pointerAbortRef.current.signal });
    window.addEventListener("pointerup", finishWindowPitchDrag, { passive: false, signal: pointerAbortRef.current.signal });
    window.addEventListener("pointercancel", cancelWindowPitchDrag, { passive: false, signal: pointerAbortRef.current.signal });

    if (!canDragPlayers) return;
    event.preventDefault();
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      // Some mobile browsers may drop capture during layout changes; window listeners keep the drag alive.
    }
    holdTimerRef.current = setTimeout(() => {
      const pointer = pointerRef.current;
      if (!pointer || pointer.pointerId !== event.pointerId) return;
      activatePitchDrag(pointer, event.clientX, event.clientY);
    }, 180);
  }

  return (
    <div
      ref={pitchRef}
      className={`match-pitch ${isLandscapePitch ? "match-pitch-horizontal" : ""} ${canDragPlayers ? "lineup-drag-enabled" : ""} ${dragState ? "lineup-drag-active" : ""} ${boardMode ? "pitch-board-mode" : ""} ${boardMode && !boardPlayersVisible ? "pitch-board-hide-players" : ""} ${className}`.trim()}
      aria-label={boardMode ? "Pizarra táctica temporal" : "Campo completo con alineaciones"}
      onPointerDown={startBoardDrawing}
    >
      {(onZoom || canUseBoard) ? (
        <div className="pitch-board-toolbar" aria-label="Herramientas del campo">
          {onZoom ? (
            <button
              className="pitch-zoom-button"
              type="button"
              onClick={onZoom}
              title="Ver campo en grande"
              aria-label="Ver campo en grande"
            >
              <SearchLogo />
            </button>
          ) : null}
          {canUseBoard ? (
            <button
              className={`pitch-board-button ${boardMode ? "active" : ""}`}
              type="button"
              onClick={toggleBoardMode}
              title={boardMode ? "Salir de pizarra" : "Modo pizarra"}
              aria-label={boardMode ? "Salir de modo pizarra" : "Entrar en modo pizarra"}
            >
              <BoardLogo />
            </button>
          ) : null}
          {boardMode ? (
            <>
              <button
                className={`pitch-board-color-button team-a ${boardState.color === "team-a" ? "active" : ""}`}
                type="button"
                onClick={() => selectBoardColor("team-a")}
                title="Dibujar con color del equipo 1"
                aria-label="Dibujar con color del equipo 1"
              >
                <span />
              </button>
              <button
                className={`pitch-board-color-button team-b ${boardState.color === "team-b" ? "active" : ""}`}
                type="button"
                onClick={() => selectBoardColor("team-b")}
                title="Dibujar con color del equipo 2"
                aria-label="Dibujar con color del equipo 2"
              >
                <span />
              </button>
              <button
                className={`pitch-board-button ${!boardPlayersVisible ? "active" : ""}`}
                type="button"
                onClick={toggleBoardPlayersVisible}
                title={boardPlayersVisible ? "Ocultar fichas" : "Mostrar fichas"}
                aria-label={boardPlayersVisible ? "Ocultar fichas de la pizarra" : "Mostrar fichas de la pizarra"}
              >
                <EyeSlashLogo />
              </button>
              <button
                className="pitch-board-button"
                type="button"
                onClick={resetBoardDraft}
                title="Borrar pizarra"
                aria-label="Borrar pizarra"
              >
                <EraserLogo />
              </button>
            </>
          ) : null}
        </div>
      ) : null}
      {boardMode ? (
        <svg className="pitch-board-lines" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
          {boardState.lines.map((line) => (
            <polyline className={`pitch-board-line-${line.color}`} key={line.id} points={line.points.map((point) => `${point.x},${point.y}`).join(" ")} />
          ))}
        </svg>
      ) : null}
      {balanceSummary ? (
        <div className="pitch-balance-hud" title={balanceSummary.detail} aria-label={`Equilibrio de equipos: ${balanceSummary.percent > 0 ? `${balanceSummary.percent}%` : "pendiente"}`}>
          <span>Equilibrio</span>
          <strong>{balanceSummary.percent > 0 ? `${balanceSummary.percent}%` : "Pendiente"}</strong>
          <i aria-hidden="true">
            <b style={{ width: `${balanceSummary.percent}%` }} />
          </i>
          <small>{balanceSummary.label}</small>
          {balanceSummary.compactEdge ? <em>{balanceSummary.compactEdge}</em> : null}
        </div>
      ) : null}
      <div className={`pitch-label ${isLandscapePitch ? "left" : "bottom"}`}>Equipo 1</div>
      <div className={`pitch-label ${isLandscapePitch ? "right" : "top"}`}>Equipo 2</div>
      <div className={`midline ${isLandscapePitch ? "vertical" : ""}`} />
      <div className="center-circle" />
      <div className={`goal-box ${isLandscapePitch ? "left" : "top"}`} />
      <div className={`goal-box ${isLandscapePitch ? "right" : "bottom"}`} />
      {tokens.length === 0 ? <p>Marca jugadores como “Voy”.</p> : null}
      {emptySlots.map((slot, index) => {
        const dropId = `slot:${slot.side}:${slot.slotIndex}`;
        const isDropTarget = dragState?.targetId === dropId;

        return (
          <div
            className={`empty-token ${slot.variant} ${isDropTarget ? "drop-target-token" : ""}`}
            data-pitch-drop-id={dropId}
            key={`${slot.variant}-empty-${index}`}
            style={{ left: `${slot.x}%`, top: `${slot.y}%` }}
            title="Falta jugador"
          >
            <b>Falta</b>
          </div>
        );
      })}
      {tokens.map(({ player, x, y, variant }) => {
        const score = scoreForPlayer(player);
        const isLineupDragging = dragState?.sourceId === player.id;
        const isDragging = isLineupDragging || boardDraggingPlayerId === player.id;
        const isDropTarget = dragState?.targetId === `player:${player.id}`;
        const boardPosition = boardMode ? boardState.playerPositions[player.id] : undefined;
        const displayedX = boardPosition?.x ?? x;
        const displayedY = boardPosition?.y ?? y;
        const tokenStyle = {
          left: `${displayedX}%`,
          top: `${displayedY}%`,
          "--drag-x": isLineupDragging ? `${dragState.dx}px` : "0px",
          "--drag-y": isLineupDragging ? `${dragState.dy}px` : "0px",
        } as CSSProperties;

        return (
          <button
            aria-label={`${playerDisplayName(player)} en el campo`}
            className={`pitch-player-card ${cardTierClass(score)} ${variant} ${isDragging ? "dragging-token" : ""} ${isDropTarget ? "drop-target-token" : ""} ${player.injured ? "injured-token" : ""} ${player.inactive ? "inactive-token" : ""}`}
            data-pitch-drop-id={`player:${player.id}`}
            data-pitch-player-id={player.id}
            key={player.id}
            onPointerCancel={clearPitchDrag}
            onPointerDown={(event) => startBoardPlayerDrag(event, player.id, { x, y })}
            style={tokenStyle}
            title={`${playerDisplayName(player)} · ${positionLabel(player)} · ${overallScore(score)}`}
            type="button"
          >
            {player.inactive ? (
              <span className="token-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                <UserOffLogo />
              </span>
            ) : null}
            {player.injured ? (
              <span className="token-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                <HospitalLogo />
              </span>
            ) : null}
            <span className="pitch-card-score">{overallScore(score)}</span>
            {renderRatingTrendChip(player)}
            <span className="pitch-card-position">{positionShort(player)}</span>
            <span className="pitch-card-photo">
              {player.avatar ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={player.avatar} alt="" draggable={false} style={avatarImageStyle(player)} />
              ) : (
                <b>{playerDisplayName(player).slice(0, 2).toUpperCase()}</b>
              )}
            </span>
            <strong>{playerDisplayName(player).split(" ")[0]}</strong>
          </button>
        );
      })}
    </div>
  );
}

function extraPitchPosition(side: "bottom" | "left" | "right" | "top", extraIndex: number) {
  if (side === "left" || side === "right") {
    const lane = extraIndex % 4;
    const row = Math.floor(extraIndex / 4);
    return {
      x: side === "left" ? 14 + lane * 8 : 86 - lane * 8,
      y: row % 2 === 0 ? 90 : 10,
    };
  }

  const lane = extraIndex % 4;
  const row = Math.floor(extraIndex / 4);
  return {
    x: row % 2 === 0 ? 90 : 10,
    y: side === "top" ? 14 + lane * 8 : 86 - lane * 8,
  };
}

function placeTeam(players: Player[], kind: MatchKind, side: "bottom" | "left" | "right" | "top", scoreForPlayer: PlayerScoreFn = scorePlayer, lineupSlotIds?: LineupSlotPlayerId[]) {
  const slots = formationSlots(kind, side).map((slot, slotIndex) => ({ ...slot, slotIndex }));
  const usesManualSlots = Boolean(lineupSlotIds?.length);

  if (usesManualSlots) {
    const playersById = new Map(players.map((player) => [player.id, player]));
    const slotPlayerIds = pitchSlotPlayerIds(players, lineupSlotIds, scoreForPlayer, slots.length);
    const placedPlayers = slotPlayerIds
      .map((playerId, index) => {
        if (!playerId) return null;
        const player = playersById.get(playerId);
        if (!player) return null;

        if (index >= slots.length) {
          return { player, slotIndex: index, ...extraPitchPosition(side, index - slots.length) };
        }

        const slot = slots[index];
        slot.used = true;
        return { player, slotIndex: slot.slotIndex, x: slot.x, y: slot.y };
      })
      .filter((token): token is { player: Player; slotIndex: number; x: number; y: number } => Boolean(token));

    return {
      players: placedPlayers,
      empty: slots.filter((slot) => !slot.used).map((slot) => ({ slotIndex: slot.slotIndex, x: slot.x, y: slot.y })),
    };
  }

  const sorted = pitchOrderedPlayers(players, lineupSlotIds, scoreForPlayer);

  const placedPlayers = sorted.map((player, index) => {
    const manual = usesManualSlots ? slots.find((slot) => !slot.used) : undefined;
    const preferred = usesManualSlots ? undefined : slots.find((slot) => slot.position === playerPosition(player) && !slot.used);
    const fallback = slots.find((slot) => !slot.used) ?? slots[slots.length - 1];
    const slot = manual ?? preferred ?? fallback;
    slot.used = true;

    if (index >= slots.length) {
      return { player, slotIndex: index, ...extraPitchPosition(side, index - slots.length) };
    }

    return { player, slotIndex: slot.slotIndex, x: slot.x, y: slot.y };
  });

  return {
    players: placedPlayers,
    empty: slots.filter((slot) => !slot.used).map((slot) => ({ slotIndex: slot.slotIndex, x: slot.x, y: slot.y })),
  };
}

function formationSlots(kind: MatchKind, side: "bottom" | "left" | "right" | "top") {
  const rows: Record<MatchKind, Array<{ position: PositionLine; count: number; y: number }>> = {
    sala: [
      { position: "Porteria", count: 1, y: 6 },
      { position: "Defensa", count: 1, y: 20 },
      { position: "Medio", count: 2, y: 32 },
      { position: "Ataque", count: 1, y: 43 },
    ],
    futbol7: [
      { position: "Porteria", count: 1, y: 6 },
      { position: "Defensa", count: 2, y: 18 },
      { position: "Medio", count: 3, y: 31 },
      { position: "Ataque", count: 1, y: 43 },
    ],
    futbol11: [
      { position: "Porteria", count: 1, y: 5 },
      { position: "Defensa", count: 4, y: 16 },
      { position: "Medio", count: 4, y: 30 },
      { position: "Ataque", count: 2, y: 43 },
    ],
  };

  return rows[kind].flatMap((row) => {
    if (side === "left" || side === "right") {
      return spreadX(row.count).map((y) => ({
        position: row.position,
        x: side === "left" ? row.y : 100 - row.y,
        y,
        used: false,
      }));
    }

    return spreadX(row.count).map((x) => ({
      position: row.position,
      x,
      y: side === "top" ? row.y : 100 - row.y,
      used: false,
    }));
  });
}

function spreadX(count: number) {
  if (count === 1) return [50];
  if (count === 2) return [32, 68];
  const gap = Math.min(70 / (count - 1), 22);
  const start = 50 - (gap * (count - 1)) / 2;
  return Array.from({ length: count }, (_, index) => start + gap * index);
}
