"use client";

import NextImage from "next/image";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { OfficialMarketGameView, type OfficialMarketTab } from "../_components/official-market-game-view";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { useAdminViewPreview } from "../admin-view-preview";
import { attachVenueAutocomplete, type VenuePlace } from "../googlePlacesClient";
import { googleAuthEntryHref } from "../google-auth-return";
import { supabase } from "../supabaseClient";
import { ChallengeableTeamsPanel } from "./challengeable-teams-panel";
import { MarketDetailSheet } from "./market-detail-sheet";
import { MarketFilterSheet, type MarketFilterDraft } from "./market-filter-sheet";
import {
  marketQueryPhase,
  visibleMarketResultCount,
  type MarketDataSource,
} from "./marketplace-ui-state";
import {
  MARKET_QUICK_DAYS,
  marketAvailabilityMatches,
  marketDayMatches,
  marketRouteDetailFromParams,
  marketRouteFiltersFromParams,
  readMarketLocationPreference,
  readMarketReadCache,
  safeMarketError,
  updateMarketRouteParams,
  writeMarketLocationPreference,
  writeMarketReadCache,
  type MarketRouteDetail,
  type MarketRouteFilters,
  type MarketSort,
} from "./market-ui-contract";
import styles from "./marketplace-v3d.module.css";

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;

function LocationTargetIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="6" />
      <circle cx="12" cy="12" r="2" />
      <path d="M12 2v4M12 18v4M2 12h4M18 12h4" />
    </svg>
  );
}

type MarketTab = "equipos" | "jugadores" | "partidos";
type MarketOperationState = { message: string; pending?: boolean; tone?: "danger" | "neutral" | "success" };

type MarketZone = {
  city?: string;
  lat?: number;
  lng?: number;
  name: string;
  placeId: string;
  province?: string;
  radiusKm: number;
};

type MarketTarget = { lat?: number; lng?: number; name: string; placeId?: string };

type MarketProfile = {
  active: boolean;
  appearances: number;
  availabilityText: string;
  avatar?: string;
  avatarOffsetX?: number;
  avatarOffsetY?: number;
  bio: string;
  displayName: string;
  goals: number;
  goalkeeperOnly: boolean;
  groupName?: string;
  id: string;
  media: number;
  modalities: string[];
  openToGroup: boolean;
  openToGuest: boolean;
  position: string;
  wins: number;
  zones: string[];
  zonesGeo: MarketZone[];
};

type MarketRow = {
  active: boolean | null;
  appearances: number | string | null;
  availability_text: string | null;
  avatar: string | null;
  avatar_offset_x: number | string | null;
  avatar_offset_y: number | string | null;
  bio: string | null;
  display_name: string | null;
  goals: number | string | null;
  goalkeeper_only: boolean | null;
  group_name: string | null;
  id: string;
  media: number | string | null;
  modalities: string[] | null;
  open_to_group: boolean | null;
  open_to_guest: boolean | null;
  position: string | null;
  wins: number | string | null;
  zones: string[] | null;
  zones_geo?: unknown | null;
};

type OpenMarketMatch = {
  active: boolean;
  confirmedCount: number;
  date: string;
  dateText: string;
  day: string;
  fieldName: string;
  groupLevel: number | null;
  groupName: string;
  guestsPay: boolean;
  id: string;
  lat?: number;
  lng?: number;
  maxRating: number;
  minRating: number;
  modality: string;
  openSlots: number;
  positions: string[];
  pricePerPlayer: number;
  requiresApproval: boolean;
  sourcePayloadRevision: number;
  targetPlayers: number;
  title: string;
  zone: string;
};

type OpenMarketMatchRow = {
  active: boolean | null;
  confirmed_count: number | string | null;
  date: string | null;
  date_text: string | null;
  day: string | null;
  field_name: string | null;
  group_level: number | string | null;
  group_name: string | null;
  guests_pay: boolean | null;
  id: string;
  lat: number | string | null;
  lng: number | string | null;
  max_media: number | string | null;
  min_media: number | string | null;
  modality: string | null;
  open_slots: number | string | null;
  positions: string[] | null;
  price_per_player: number | string | null;
  requires_approval: boolean | null;
  source_payload_revision: number | string | null;
  target_players: number | string | null;
  title: string | null;
  zone: string | null;
};

type OpenMatchRequestStatus = "accepted" | "cancelled" | "pending" | "rejected";
type OpenMatchRequestSummary = {
  actionUrl?: string;
  id: string;
  matchRevision: number;
  openMatchId: string;
  revision: number;
  serverSequence: number;
  status: OpenMatchRequestStatus;
};
type OpenMatchRequestSummaryRow = {
  action_url?: string | null;
  id: string;
  match_revision: number | string | null;
  open_match_id: string | null;
  revision: number | string | null;
  server_sequence: number | string | null;
  status: string | null;
};
type MatchInvitationSummary = {
  id: string;
  revision: number;
  status: "accepted" | "cancelled" | "pending" | "rejected";
  targetMarketProfileId: string;
};

type IncomingMatchInvitation = {
  createdAt: string;
  groupId: string;
  invitationId: string;
  matchDate: string;
  matchId: string;
  matchKind: string;
  matchPlace: string;
  matchRevision: number;
  matchTitle: string;
  revision: number;
  status: "accepted" | "cancelled" | "pending" | "rejected";
  teamName: string;
  updatedAt: string;
};

type MarketMatchContext = {
  dateText: string;
  day: string;
  groupId: string;
  lat?: number;
  lng?: number;
  matchId: string;
  matchUrl: string;
  missing: string;
  modality: string;
  placeId?: string;
  revision: number;
  requesterKind: "CLUB" | "COMPETITION" | "TEAM";
  title: string;
  zone: string;
};

type InitialMarketRoute = {
  context: MarketMatchContext | null;
  detail: MarketRouteDetail;
  filters: MarketRouteFilters;
  tab: MarketTab;
  zonePlace: MarketTarget | null;
};

const modalityLabels: Record<string, string> = {
  futbol11: "Fútbol 11",
  futbol7: "Fútbol 7",
  sala: "Fútbol sala",
};

function marketOperationMetadata() {
  const storageKey = "pachangas-operation-session";
  let sessionId = window.sessionStorage.getItem(storageKey);
  if (!sessionId) {
    sessionId = crypto.randomUUID();
    window.sessionStorage.setItem(storageKey, sessionId);
  }
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    sessionId,
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-market" : "web-market",
  };
}

function marketTabFromParam(value: string | null): MarketTab {
  if (value === "equipos" || value === "jugadores" || value === "partidos") return value;
  return "partidos";
}

function numberParam(value: string | null) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : undefined;
}

export function marketRouteFromSearch(search: string): InitialMarketRoute {
  const params = new URLSearchParams(search);
  const filters = marketRouteFiltersFromParams(params);
  const detail = marketRouteDetailFromParams(params);
  const tab = marketTabFromParam(params.get("tab"));
  const matchId = params.get("partido");
  const lat = numberParam(params.get("lat"));
  const lng = numberParam(params.get("lng"));
  const zonePlace = filters.zone ? { lat, lng, name: filters.zone, placeId: filters.zonePlaceId } : null;
  if (!matchId) return { context: null, detail, filters, tab, zonePlace };
  const requesterKindValue = params.get("requesterKind");
  const requesterKind = requesterKindValue === "CLUB" || requesterKindValue === "COMPETITION" ? requesterKindValue : "TEAM";
  return {
    context: {
      dateText: params.get("fecha") || "",
      day: filters.day,
      groupId: params.get("grupoId") || "",
      lat,
      lng,
      matchId,
      matchUrl: params.get("link") || "",
      missing: params.get("plazas") || "",
      modality: filters.modality,
      placeId: filters.zonePlaceId,
      revision: Math.max(0, Math.floor(numberParam(params.get("revision")) ?? 0)),
      requesterKind,
      title: params.get("titulo") || "Partido",
      zone: filters.zone,
    },
    detail,
    filters,
    tab,
    zonePlace,
  };
}

function createFilterDraft(filters: MarketRouteFilters): MarketFilterDraft {
  return { ...filters, approval: "all", goalkeeperOnly: false, openSlotsOnly: true };
}

function normalizeMarketZoneRadius(value: unknown) {
  const radius = Number(value);
  return [0, 5, 10, 20, 30, 50, 75, 100].includes(radius) ? radius : 0;
}

function normalizeZones(value: unknown, legacy: string[] = []) {
  if (!Array.isArray(value)) return legacy.map((name, index) => ({ name, placeId: `legacy-${index}-${name}`, radiusKm: 0 }));
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const row = item as Partial<MarketZone>;
    const name = typeof row.name === "string" ? row.name.trim() : "";
    const placeId = typeof row.placeId === "string" ? row.placeId.trim() : "";
    if (!name || !placeId) return [];
    const lat = Number(row.lat);
    const lng = Number(row.lng);
    return [{
      city: typeof row.city === "string" ? row.city : undefined,
      lat: Number.isFinite(lat) ? lat : undefined,
      lng: Number.isFinite(lng) ? lng : undefined,
      name,
      placeId,
      province: typeof row.province === "string" ? row.province : undefined,
      radiusKm: normalizeMarketZoneRadius(row.radiusKm),
    }];
  });
}

function normalizeProfile(row: MarketRow): MarketProfile {
  const zones = Array.isArray(row.zones) ? row.zones.filter((zone): zone is string => typeof zone === "string") : [];
  return {
    active: row.active !== false,
    appearances: Math.max(0, Number(row.appearances) || 0),
    availabilityText: row.availability_text || "",
    avatar: row.avatar || undefined,
    avatarOffsetX: Number(row.avatar_offset_x) || 0,
    avatarOffsetY: Number(row.avatar_offset_y) || 0,
    bio: row.bio || "",
    displayName: row.display_name || "Jugador",
    goals: Math.max(0, Number(row.goals) || 0),
    goalkeeperOnly: row.goalkeeper_only === true,
    groupName: row.group_name || undefined,
    id: row.id,
    media: Number(row.media) || 0,
    modalities: Array.isArray(row.modalities) ? row.modalities : [],
    openToGroup: row.open_to_group === true,
    openToGuest: row.open_to_guest === true,
    position: row.position || "Sin posición",
    wins: Math.max(0, Number(row.wins) || 0),
    zones,
    zonesGeo: normalizeZones(row.zones_geo, zones),
  };
}

function normalizeOpenMatch(row: OpenMarketMatchRow): OpenMarketMatch {
  const confirmedCount = Math.max(0, Math.floor(Number(row.confirmed_count) || 0));
  const targetPlayers = Math.max(1, Math.floor(Number(row.target_players) || confirmedCount || 1));
  return {
    active: row.active !== false,
    confirmedCount,
    date: row.date || "",
    dateText: row.date_text || row.date || "Fecha por confirmar",
    day: row.day || "",
    fieldName: row.field_name || "Campo por confirmar",
    groupLevel: row.group_level === null ? null : Number(row.group_level) || null,
    groupName: row.group_name || "Grupo organizador",
    guestsPay: row.guests_pay === true,
    id: row.id,
    lat: row.lat === null ? undefined : Number(row.lat),
    lng: row.lng === null ? undefined : Number(row.lng),
    maxRating: Number(row.max_media) || 10,
    minRating: Number(row.min_media) || 0,
    modality: row.modality || "futbol7",
    openSlots: Math.max(0, Math.floor(Number(row.open_slots) || 0)),
    positions: Array.isArray(row.positions) ? row.positions : [],
    pricePerPlayer: Math.max(0, Number(row.price_per_player) || 0),
    requiresApproval: row.requires_approval !== false,
    sourcePayloadRevision: Math.max(0, Math.floor(Number(row.source_payload_revision) || 0)),
    targetPlayers,
    title: row.title || "Partido abierto",
    zone: row.zone || "Zona por confirmar",
  };
}

function normalizeIncomingMatchInvitation(value: unknown): IncomingMatchInvitation | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  if (typeof row.invitationId !== "string" || typeof row.matchId !== "string") return null;
  const status = row.status === "accepted" || row.status === "cancelled" || row.status === "rejected" ? row.status : "pending";
  return {
    createdAt: typeof row.createdAt === "string" ? row.createdAt : "",
    groupId: typeof row.groupId === "string" ? row.groupId : "",
    invitationId: row.invitationId,
    matchDate: typeof row.matchDate === "string" ? row.matchDate : "",
    matchId: row.matchId,
    matchKind: typeof row.matchKind === "string" ? row.matchKind : "futbol7",
    matchPlace: typeof row.matchPlace === "string" ? row.matchPlace : "",
    matchRevision: Math.max(0, Math.floor(Number(row.matchRevision) || 0)),
    matchTitle: typeof row.matchTitle === "string" ? row.matchTitle : "Partido",
    revision: Math.max(1, Math.floor(Number(row.revision) || 1)),
    status,
    teamName: typeof row.teamName === "string" ? row.teamName : "Equipo",
    updatedAt: typeof row.updatedAt === "string" ? row.updatedAt : "",
  };
}

function normalizeText(value: string) {
  return value.toLocaleLowerCase("es").normalize("NFD").replace(/\p{Diacritic}/gu, "");
}

function overall(media: number) {
  return Math.max(0, Math.min(100, Math.round(media <= 10 ? media * 10 : media)));
}

function distanceKmBetween(origin: MarketTarget | null, lat?: number, lng?: number) {
  if (!origin || !Number.isFinite(origin.lat) || !Number.isFinite(origin.lng) || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const toRadians = (value: number) => value * Math.PI / 180;
  const lat1 = toRadians(origin.lat as number);
  const lat2 = toRadians(lat as number);
  const deltaLat = lat2 - lat1;
  const deltaLng = toRadians((lng as number) - (origin.lng as number));
  const a = Math.sin(deltaLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function zoneLabel(zone: MarketZone) {
  return [zone.city || zone.name, zone.province].filter(Boolean).join(", ");
}

function profileZone(profile: MarketProfile, target: MarketTarget | null, query: string) {
  const normalizedQuery = normalizeText(query.trim());
  let bestDistance: number | null = null;
  let bestLabel = profile.zones[0] || "Zona por definir";
  for (const zone of profile.zonesGeo) {
    const distance = distanceKmBetween(target, zone.lat, zone.lng);
    if (distance !== null && (bestDistance === null || distance < bestDistance)) {
      bestDistance = distance;
      bestLabel = zoneLabel(zone);
    }
  }
  const textMatch = !normalizedQuery || [...profile.zones, ...profile.zonesGeo.map(zoneLabel)]
    .some((value) => normalizeText(value).includes(normalizedQuery));
  return { distanceKm: bestDistance, label: bestLabel, matches: bestDistance !== null ? true : textMatch };
}

function positionMatches(profile: MarketProfile, filter: string) {
  if (filter === "Todas") return true;
  const position = normalizeText(profile.position);
  if (filter === "Portero") return profile.goalkeeperOnly || position.includes("portero");
  if (filter === "Defensa") return /defensa|lateral|cierre|carrilero/.test(position);
  if (filter === "Medio") return /medio|pivote|interior|volante|ala/.test(position);
  if (filter === "Ataque") return /delantero|punta|extremo|pivot/.test(position);
  return true;
}

function avatarStyle(profile: MarketProfile) {
  return { objectPosition: `${50 + (profile.avatarOffsetX || 0)}% ${50 + (profile.avatarOffsetY || 0)}%` };
}

function matchHrefFromRequest(request?: OpenMatchRequestSummary) {
  return request?.actionUrl || null;
}

function marketAdminMatchUrl(matchUrl: string) {
  if (!matchUrl) return "/?mobile=partido&pane=admin";
  return `${matchUrl}${matchUrl.includes("?") ? "&" : "?"}mobile=partido&pane=admin`;
}

function sourceLabel(source: MarketDataSource, updatedAt: string | null, online: boolean) {
  if (!online && source === "CACHED") return `Resultados guardados · ${updatedAt ? new Date(updatedAt).toLocaleString("es-ES") : "sin fecha"}`;
  if (source === "CACHED") return `Guardados · ${updatedAt ? new Date(updatedAt).toLocaleString("es-ES") : "sin fecha"}`;
  if (source === "IDLE") return "Sin consultar";
  if (source === "LOADING") return "Buscando";
  if (source === "UNAVAILABLE") return "No disponible";
  return "Actualizado";
}

export default function MarketplaceClient() {
  const [initialRoute] = useState(() => marketRouteFromSearch(""));
  const [activeTab, setActiveTab] = useState<MarketTab>(initialRoute.tab);
  const [filters, setFilters] = useState<MarketFilterDraft>(() => createFilterDraft(initialRoute.filters));
  const [filterDraft, setFilterDraft] = useState<MarketFilterDraft>(() => createFilterDraft(initialRoute.filters));
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [selectedDetail, setSelectedDetail] = useState<MarketRouteDetail>(initialRoute.detail);
  const [marketContext, setMarketContext] = useState<MarketMatchContext | null>(initialRoute.context);
  const [zonePlace, setZonePlace] = useState<MarketTarget | null>(initialRoute.zonePlace);
  const [locationMessage, setLocationMessage] = useState("");
  const [profiles, setProfiles] = useState<MarketProfile[]>([]);
  const [openMatches, setOpenMatches] = useState<OpenMarketMatch[]>([]);
  const [profileSource, setProfileSource] = useState<MarketDataSource>("LOADING");
  const [matchSource, setMatchSource] = useState<MarketDataSource>("LOADING");
  const [teamSource, setTeamSource] = useState<MarketDataSource>("LOADING");
  const [cacheUpdatedAt, setCacheUpdatedAt] = useState<string | null>(null);
  const [openMatchRequests, setOpenMatchRequests] = useState<Record<string, OpenMatchRequestSummary>>({});
  const [matchInvitations, setMatchInvitations] = useState<Record<string, MatchInvitationSummary>>({});
  const [operations, setOperations] = useState<Record<string, MarketOperationState>>({});
  const [currentUserId, setCurrentUserId] = useState("");
  const [canInvite, setCanInvite] = useState(false);
  const [marketRefresh, setMarketRefresh] = useState(0);
  const [incomingInvitationId, setIncomingInvitationId] = useState("");
  const [incomingInvitation, setIncomingInvitation] = useState<IncomingMatchInvitation | null>(null);
  const [incomingInvitationState, setIncomingInvitationState] = useState<"error" | "idle" | "loading" | "ready" | "responding" | "signed-out">("idle");
  const [incomingInvitationMessage, setIncomingInvitationMessage] = useState("");
  const [incomingInvitationRefresh, setIncomingInvitationRefresh] = useState(0);
  const [online, setOnline] = useState(true);
  const [locating, setLocating] = useState(false);
  const zoneInputRef = useRef<HTMLInputElement>(null);
  const { previewRequested, toggleAdminViewPreview } = useAdminViewPreview();
  const playerPreviewActive = canInvite && previewRequested;
  const canUseMarketAdminControls = canInvite && !playerPreviewActive;
  const marketGroupId = marketContext?.groupId ?? "";
  const marketMatchId = marketContext?.matchId ?? "";

  const restoreMarketRoute = useEffectEvent((route: InitialMarketRoute) => {
    setActiveTab(route.tab);
    setMarketContext(route.context);
    setSelectedDetail(route.detail);
    setFilters((current) => ({ ...createFilterDraft(route.filters), approval: current.approval, goalkeeperOnly: current.goalkeeperOnly, openSlotsOnly: current.openSlotsOnly }));
    setFilterDraft((current) => ({ ...createFilterDraft(route.filters), approval: current.approval, goalkeeperOnly: current.goalkeeperOnly, openSlotsOnly: current.openSlotsOnly }));
    setZonePlace(route.zonePlace);
  });

  useEffect(() => {
    let active = true;
    const restore = () => {
      const params = new URLSearchParams(window.location.search);
      if (params.get("tab") === "retos") {
        window.location.replace("/retos");
        return;
      }
      const route = marketRouteFromSearch(window.location.search);
      setIncomingInvitationId(params.get("invitacion")?.trim() ?? "");
      window.queueMicrotask(() => {
        if (active) restoreMarketRoute(route);
      });
    };
    restore();
    const params = new URLSearchParams(window.location.search);
    if (!params.get("zona") && !params.get("partido")) {
      const preference = readMarketLocationPreference(window.localStorage);
      if (preference) {
        window.queueMicrotask(() => {
          if (!active) return;
          setFilters((current) => ({ ...current, radiusKm: preference.radiusKm, zone: preference.label, zonePlaceId: preference.placeId }));
          setFilterDraft((current) => ({ ...current, radiusKm: preference.radiusKm, zone: preference.label, zonePlaceId: preference.placeId }));
          setZonePlace({ name: preference.label, placeId: preference.placeId });
        });
      }
    }
    window.addEventListener("popstate", restore);
    return () => {
      active = false;
      window.removeEventListener("popstate", restore);
    };
  }, []);

  useEffect(() => {
    let disposed = false;
    async function loadInvitation() {
      if (!incomingInvitationId) {
        setIncomingInvitation(null);
        setIncomingInvitationState("idle");
        setIncomingInvitationMessage("");
        return;
      }
      if (!currentUserId) {
        setIncomingInvitation(null);
        setIncomingInvitationState("signed-out");
        return;
      }
      if (!online || !supabase) {
        setIncomingInvitationState("error");
        setIncomingInvitationMessage("Necesitas conexión para consultar y responder esta invitación.");
        return;
      }
      setIncomingInvitationState("loading");
      setIncomingInvitationMessage("");
      const result = await supabase.rpc("get_my_pachanga_match_invitation_action_v1", {
        target_invitation_id: incomingInvitationId,
      });
      if (disposed) return;
      if (result.error) {
        const safe = safeMarketError(result.error);
        setIncomingInvitation(null);
        setIncomingInvitationState("error");
        setIncomingInvitationMessage(safe.body || "Esta invitación ya no está disponible.");
        return;
      }
      const normalized = normalizeIncomingMatchInvitation(result.data);
      if (!normalized) {
        setIncomingInvitation(null);
        setIncomingInvitationState("error");
        setIncomingInvitationMessage("El servidor no devolvió una invitación válida.");
        return;
      }
      setIncomingInvitation(normalized);
      setIncomingInvitationState("ready");
    }
    void loadInvitation();
    return () => { disposed = true; };
  }, [currentUserId, incomingInvitationId, incomingInvitationRefresh, online]);

  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  useEffect(() => {
    let active = true;
    const cached = readMarketReadCache<MarketProfile, OpenMarketMatch>(window.localStorage);
    const restoreCachedProfiles = () => {
      if (!cached?.profiles.length) return false;
      setProfiles(cached.profiles);
      setProfileSource("CACHED");
      setCacheUpdatedAt(cached.updatedAt);
      return true;
    };
    const restoreCachedMatches = () => {
      if (!cached?.matches.length) return false;
      setOpenMatches(cached.matches);
      setMatchSource("CACHED");
      setCacheUpdatedAt(cached.updatedAt);
      return true;
    };

    async function loadMarket() {
      if (!supabase || !navigator.onLine) {
        if (!restoreCachedProfiles()) setProfileSource("UNAVAILABLE");
        if (!restoreCachedMatches()) setMatchSource("UNAVAILABLE");
        return;
      }
      setProfileSource((current) => current === "CACHED" ? current : "LOADING");
      setMatchSource((current) => current === "CACHED" ? current : "LOADING");
      const session = await supabase.auth.getSession();
      const user = session.data.session?.user ?? null;
      if (!active) return;
      setCurrentUserId(user?.id ?? "");

      let exactCanInvite = false;
      if (user && marketGroupId && marketContext?.requesterKind === "TEAM") {
        const membership = await supabase
          .from("pachanga_group_members")
          .select("role")
          .eq("group_id", marketGroupId)
          .eq("user_id", user.id)
          .maybeSingle();
        exactCanInvite = !membership.error && ["owner", "admin"].includes(String(membership.data?.role));
      }
      if (!active) return;
      setCanInvite(exactCanInvite);

      const columns = "id, display_name, avatar, avatar_offset_x, avatar_offset_y, birth_date, position, goalkeeper_only, media, appearances, goals, wins, zones, zones_geo, availability_text, modalities, open_to_guest, open_to_group, bio, active, group_name";
      const legacyColumns = "id, display_name, avatar, avatar_offset_x, avatar_offset_y, birth_date, position, goalkeeper_only, media, appearances, goals, wins, zones, availability_text, modalities, open_to_guest, open_to_group, bio, active, group_name";
      let profileResult = (await supabase
        .from("pachanga_market_profiles")
        .select(columns)
        .eq("active", true)
        .order("media", { ascending: false })
        .limit(80)) as { data: unknown[] | null; error: { message: string } | null };
      if (profileResult.error?.message.includes("zones_geo")) {
        profileResult = (await supabase
          .from("pachanga_market_profiles")
          .select(legacyColumns)
          .eq("active", true)
          .order("media", { ascending: false })
          .limit(80)) as { data: unknown[] | null; error: { message: string } | null };
      }
      if (!active) return;
      const nextProfiles = profileResult.error ? null : (profileResult.data as MarketRow[]).map(normalizeProfile);
      if (nextProfiles) {
        setProfiles(nextProfiles);
        setProfileSource("LIVE");
      } else if (!restoreCachedProfiles()) {
        setProfiles([]);
        setProfileSource("UNAVAILABLE");
      }

      let nextMatches: OpenMarketMatch[] | null = null;
      if (user) {
        const matchResult = await supabase.rpc("search_pachanga_open_matches_v1");
        if (!active) return;
        if (!matchResult.error) {
          nextMatches = (Array.isArray(matchResult.data) ? matchResult.data : []).map((row) => normalizeOpenMatch(row as OpenMarketMatchRow));
          setOpenMatches(nextMatches);
          setMatchSource("LIVE");
        } else if (!restoreCachedMatches()) {
          setOpenMatches([]);
          setMatchSource("UNAVAILABLE");
        }

        const requestResult = await supabase.rpc("get_my_pachanga_open_match_requests_v1");
        if (!requestResult.error && active) {
          const nextRequests = (Array.isArray(requestResult.data) ? requestResult.data : []).reduce<Record<string, OpenMatchRequestSummary>>((items, value) => {
            const row = value as OpenMatchRequestSummaryRow;
            if (!row.open_match_id) return items;
            const status = row.status === "accepted" || row.status === "rejected" || row.status === "cancelled" ? row.status : "pending";
            items[row.open_match_id] = {
              actionUrl: row.action_url ?? undefined,
              id: row.id,
              matchRevision: Math.max(0, Math.floor(Number(row.match_revision) || 0)),
              openMatchId: row.open_match_id,
              revision: Math.max(1, Math.floor(Number(row.revision) || 1)),
              serverSequence: Math.max(0, Math.floor(Number(row.server_sequence) || 0)),
              status,
            };
            return items;
          }, {});
          setOpenMatchRequests(nextRequests);
        }
      } else {
        setOpenMatchRequests({});
        if (!restoreCachedMatches()) {
          setOpenMatches([]);
          setMatchSource("IDLE");
        }
      }

      if (nextProfiles && nextMatches) {
        const updatedAt = new Date().toISOString();
        writeMarketReadCache(window.localStorage, { matches: nextMatches, profiles: nextProfiles, updatedAt, version: 1 });
        setCacheUpdatedAt(updatedAt);
      }

      if (exactCanInvite && marketGroupId && marketMatchId) {
        const invitationState = await supabase.rpc("get_pachanga_match_invitation_admin_state_v1", {
          target_group_id: marketGroupId,
          target_match_id: marketMatchId,
        });
        if (!invitationState.error && invitationState.data && typeof invitationState.data === "object" && active) {
          const payload = invitationState.data as { confirmedRevision?: number; invitations?: MatchInvitationSummary[] };
          setMatchInvitations((payload.invitations ?? []).reduce<Record<string, MatchInvitationSummary>>((items, invitation) => {
            if (invitation.targetMarketProfileId && !items[invitation.targetMarketProfileId]) items[invitation.targetMarketProfileId] = invitation;
            return items;
          }, {}));
          const confirmedRevision = Math.max(0, Math.floor(Number(payload.confirmedRevision) || 0));
          setMarketContext((current) => current ? { ...current, revision: confirmedRevision } : null);
        }
      } else {
        setMatchInvitations({});
      }
    }

    void loadMarket();
    return () => {
      active = false;
    };
  }, [marketContext?.requesterKind, marketGroupId, marketMatchId, marketRefresh, online]);

  const acceptLocationPlace = useEffectEvent((place: VenuePlace) => {
    const label = [place.city || place.name, place.province].filter(Boolean).join(", ") || place.name;
    const target = { lat: place.lat, lng: place.lng, name: label, placeId: place.placeId || undefined };
    const nextFilters = { ...filters, zone: label, zonePlaceId: target.placeId };
    setZonePlace(target);
    setFilters(nextFilters);
    setFilterDraft(nextFilters);
    setLocationMessage("");
    writeMarketLocationPreference(window.localStorage, { label, placeId: target.placeId, radiusKm: nextFilters.radiusKm });
    replaceRoute({ filters: nextFilters });
  });

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let disposed = false;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(({ data }) => {
      const user = data.session?.user;
      if (!user || disposed) return;
      channel = client.channel(`market-v3d-${user.id}-${marketGroupId || "public"}`)
        .on("postgres_changes", {
          event: "*",
          schema: "public",
          table: "pachanga_open_match_requests",
          filter: `requester_user_id=eq.${user.id}`,
        }, () => setMarketRefresh((value) => value + 1))
        .on("postgres_changes", {
          event: "*",
          schema: "public",
          table: "pachanga_user_notifications",
          filter: `recipient_user_id=eq.${user.id}`,
        }, () => setMarketRefresh((value) => value + 1));
      if (marketGroupId) {
        channel = channel.on("postgres_changes", {
          event: "UPDATE",
          schema: "public",
          table: "pachanga_groups",
          filter: `id=eq.${marketGroupId}`,
        }, () => setMarketRefresh((value) => value + 1));
      }
      channel.subscribe((status) => {
        if (status === "SUBSCRIBED") setMarketRefresh((value) => value + 1);
      });
    });
    const refreshVisible = () => {
      if (document.visibilityState === "visible" && navigator.onLine) setMarketRefresh((value) => value + 1);
    };
    document.addEventListener("visibilitychange", refreshVisible);
    return () => {
      disposed = true;
      document.removeEventListener("visibilitychange", refreshVisible);
      if (channel) void client.removeChannel(channel);
    };
  }, [marketGroupId]);

  useEffect(() => {
    if (!googleMapsApiKey || !zoneInputRef.current) return;
    let cleanup: (() => void) | undefined;
    let disposed = false;
    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input: zoneInputRef.current,
      onPlace: (place: VenuePlace) => {
        if (!disposed) acceptLocationPlace(place);
      },
      types: ["(cities)"],
    }).then((nextCleanup) => {
      if (disposed) nextCleanup();
      else cleanup = nextCleanup;
    }).catch(() => setLocationMessage("Puedes escribir la ciudad manualmente."));
    return () => {
      disposed = true;
      cleanup?.();
    };
  }, []);

  function routeUrl(params: URLSearchParams) {
    const query = params.toString();
    return `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`;
  }

  function pushRoute(values: { detail?: MarketRouteDetail; filters?: MarketRouteFilters; tab?: MarketTab }) {
    const params = updateMarketRouteParams(new URLSearchParams(window.location.search), values);
    window.history.pushState(null, "", routeUrl(params));
  }

  function replaceRoute(values: { detail?: MarketRouteDetail; filters?: MarketRouteFilters; tab?: MarketTab }) {
    const params = updateMarketRouteParams(new URLSearchParams(window.location.search), values);
    window.history.replaceState(null, "", routeUrl(params));
  }

  function selectMarketTab(tab: MarketTab) {
    setActiveTab(tab);
    setSelectedDetail(null);
    pushRoute({ detail: null, filters, tab });
  }

  function openDetail(detail: NonNullable<MarketRouteDetail>) {
    setSelectedDetail(detail);
    pushRoute({ detail, filters, tab: activeTab });
  }

  function closeDetail() {
    setSelectedDetail(null);
    pushRoute({ detail: null, filters, tab: activeTab });
  }

  function setOperation(key: string, state: MarketOperationState) {
    setOperations((current) => ({ ...current, [key]: state }));
  }

  function applyQuickFilter(patch: Partial<MarketFilterDraft>) {
    const next = { ...filters, ...patch };
    setFilters(next);
    setFilterDraft(next);
    replaceRoute({ filters: next });
  }

  function clearFilters() {
    const next = createFilterDraft({
      day: "Todos",
      maxPrice: null,
      maxRating: null,
      minRating: null,
      modality: "Todas",
      position: "Todas",
      radiusKm: 30,
      sort: "relevance",
      zone: "",
    });
    setFilters(next);
    setFilterDraft(next);
    setZonePlace(null);
    replaceRoute({ filters: next });
  }

  function useMyLocation() {
    if (!navigator.geolocation) {
      setLocationMessage("Tu navegador no permite obtener la ubicación. Puedes escribir la zona.");
      return;
    }
    setLocating(true);
    setLocationMessage("");
    navigator.geolocation.getCurrentPosition((position) => {
      const next = { ...filters, zone: "Mi ubicación aproximada", zonePlaceId: undefined };
      setLocating(false);
      setZonePlace({ lat: position.coords.latitude, lng: position.coords.longitude, name: "Mi ubicación aproximada" });
      setFilters(next);
      setFilterDraft(next);
      replaceRoute({ filters: next });
    }, () => {
      setLocating(false);
      setLocationMessage("No hemos usado tu ubicación. Puedes continuar escribiendo la ciudad.");
    }, { enableHighAccuracy: false, maximumAge: 300000, timeout: 8000 });
  }

  const activeTarget = zonePlace || (marketContext?.zone ? {
    lat: marketContext.lat,
    lng: marketContext.lng,
    name: marketContext.zone,
    placeId: marketContext.placeId,
  } : null);

  function profilesFor(activeFilters: MarketFilterDraft) {
    const normalizedZone = normalizeText(activeFilters.zone.trim());
    return profiles
      .filter((profile) => {
        const match = profileZone(profile, activeTarget, activeFilters.zone);
        const level = overall(profile.media);
        return profile.active
          && (!normalizedZone || match.matches)
          && (match.distanceKm === null || match.distanceKm <= activeFilters.radiusKm)
          && marketAvailabilityMatches(profile.availabilityText, activeFilters.day)
          && (activeFilters.modality === "Todas" || profile.modalities.includes(activeFilters.modality))
          && positionMatches(profile, activeFilters.position)
          && (!activeFilters.goalkeeperOnly || profile.goalkeeperOnly)
          && (activeFilters.minRating === null || level >= activeFilters.minRating)
          && (activeFilters.maxRating === null || level <= activeFilters.maxRating);
      })
      .sort((left, right) => {
        if (activeFilters.sort === "level") return overall(right.media) - overall(left.media);
        if (activeFilters.sort === "distance") {
          return (profileZone(left, activeTarget, activeFilters.zone).distanceKm ?? Number.MAX_SAFE_INTEGER)
            - (profileZone(right, activeTarget, activeFilters.zone).distanceKm ?? Number.MAX_SAFE_INTEGER);
        }
        const leftAvailable = left.availabilityText ? 1 : 0;
        const rightAvailable = right.availabilityText ? 1 : 0;
        return rightAvailable - leftAvailable || overall(right.media) - overall(left.media);
      });
  }

  function matchesFor(activeFilters: MarketFilterDraft) {
    const zoneQuery = normalizeText(activeFilters.zone.trim());
    return openMatches
      .filter((match) => {
        const distance = distanceKmBetween(activeTarget, match.lat, match.lng);
        const ownAccepted = openMatchRequests[match.id]?.status === "accepted";
        return (ownAccepted || match.active && (!activeFilters.openSlotsOnly || match.openSlots > 0))
          && (!zoneQuery || distance !== null || normalizeText(`${match.zone} ${match.fieldName}`).includes(zoneQuery))
          && (distance === null || distance <= activeFilters.radiusKm)
          && marketDayMatches(match.date, activeFilters.day)
          && (activeFilters.modality === "Todas" || match.modality === activeFilters.modality)
          && (activeFilters.position === "Todas" || !match.positions.length || match.positions.includes(activeFilters.position))
          && (activeFilters.maxPrice === null || match.pricePerPlayer <= activeFilters.maxPrice)
          && (activeFilters.approval === "all" || activeFilters.approval === "manual" === match.requiresApproval);
      })
      .sort((left, right) => {
        if (activeFilters.sort === "slots") return right.openSlots - left.openSlots;
        if (activeFilters.sort === "distance") {
          return (distanceKmBetween(activeTarget, left.lat, left.lng) ?? Number.MAX_SAFE_INTEGER)
            - (distanceKmBetween(activeTarget, right.lat, right.lng) ?? Number.MAX_SAFE_INTEGER);
        }
        return (Date.parse(left.date) || Number.MAX_SAFE_INTEGER) - (Date.parse(right.date) || Number.MAX_SAFE_INTEGER);
      });
  }

  const filteredProfiles = profilesFor(filters);
  const filteredMatches = matchesFor(filters);
  const draftResultCount = activeTab === "partidos" ? matchesFor(filterDraft).length : activeTab === "jugadores" ? profilesFor(filterDraft).length : 0;
  const selectedMatch = selectedDetail?.kind === "match" ? openMatches.find((match) => match.id === selectedDetail.id) ?? null : null;
  const selectedPlayer = selectedDetail?.kind === "player" ? profiles.find((profile) => profile.id === selectedDetail.id) ?? null : null;

  async function requestOpenMatch(match: OpenMarketMatch) {
    const key = `match:${match.id}`;
    if (!online) {
      setOperation(key, { message: "Necesitas conexión para confirmar esta acción.", tone: "danger" });
      return;
    }
    if (!currentUserId) {
      window.location.assign(googleAuthEntryHref(`${window.location.pathname}${window.location.search}`));
      return;
    }
    if (!supabase) {
      setOperation(key, { message: "El servicio no está disponible ahora.", tone: "danger" });
      return;
    }
    setOperation(key, { message: "Enviando solicitud…", pending: true, tone: "neutral" });
    const result = await supabase.rpc("request_pachanga_open_match_authoritative_v2", {
      client_metadata: marketOperationMetadata(),
      expected_match_revision: match.sourcePayloadRevision,
      operation_id: crypto.randomUUID(),
      target_open_match_id: match.id,
    });
    if (result.error) {
      const safe = safeMarketError(result.error);
      setOperation(key, { message: safe.body, tone: "danger" });
      if (safe.stale) setMarketRefresh((value) => value + 1);
      return;
    }
    const payload = result.data as {
      confirmedRevision?: number;
      request?: { actionUrl?: string; id?: string; openMatchId?: string; revision?: number; serverSequence?: number; status?: string };
    } | null;
    const request = payload?.request;
    const status = request?.status;
    const nextStatus: OpenMatchRequestStatus = status === "accepted" || status === "rejected" || status === "cancelled" ? status : "pending";
    setOpenMatchRequests((current) => ({
      ...current,
      [match.id]: {
        actionUrl: request?.actionUrl,
        id: request?.id || current[match.id]?.id || "",
        matchRevision: Math.max(0, Math.floor(Number(payload?.confirmedRevision) || match.sourcePayloadRevision)),
        openMatchId: request?.openMatchId || match.id,
        revision: Math.max(1, Math.floor(Number(request?.revision) || 1)),
        serverSequence: Math.max(0, Math.floor(Number(request?.serverSequence) || 0)),
        status: nextStatus,
      },
    }));
    setOperation(key, {
      message: nextStatus === "accepted" ? "Plaza confirmada." : "Solicitud enviada. El equipo organizador debe aceptarla.",
      tone: "success",
    });
  }

  async function cancelOpenMatchRequest(request: OpenMatchRequestSummary) {
    const key = `match:${request.openMatchId}`;
    if (!online || !supabase) {
      setOperation(key, { message: "Necesitas conexión para confirmar esta acción.", tone: "danger" });
      return;
    }
    setOperation(key, { message: "Cancelando solicitud…", pending: true, tone: "neutral" });
    const result = await supabase.rpc("cancel_my_pachanga_open_match_request_v1", {
      client_metadata: marketOperationMetadata(),
      expected_match_revision: request.matchRevision,
      expected_request_revision: request.revision,
      operation_id: crypto.randomUUID(),
      target_request_id: request.id,
    });
    if (result.error) {
      const safe = safeMarketError(result.error);
      setOperation(key, { message: safe.body, tone: "danger" });
      if (safe.stale) setMarketRefresh((value) => value + 1);
      return;
    }
    const payload = result.data as {
      confirmedRevision?: number;
      request?: { revision?: number; serverSequence?: number };
    } | null;
    setOpenMatchRequests((current) => ({
      ...current,
      [request.openMatchId]: {
        ...request,
        matchRevision: Math.max(0, Math.floor(Number(payload?.confirmedRevision) || request.matchRevision)),
        revision: Math.max(1, Math.floor(Number(payload?.request?.revision) || request.revision + 1)),
        serverSequence: Math.max(0, Math.floor(Number(payload?.request?.serverSequence) || request.serverSequence)),
        status: "cancelled",
      },
    }));
    setOperation(key, { message: "Solicitud cancelada.", tone: "success" });
  }

  async function toggleInvitation(profile: MarketProfile) {
    const key = `player:${profile.id}`;
    if (!online || !supabase) {
      setOperation(key, { message: "Necesitas conexión para confirmar esta acción.", tone: "danger" });
      return;
    }
    if (!marketContext || !canUseMarketAdminControls || !profile.openToGuest) {
      setOperation(key, { message: "Esta invitación no está disponible para tu rol o este partido.", tone: "danger" });
      return;
    }
    const existing = matchInvitations[profile.id];
    setOperation(key, { message: existing?.status === "pending" ? "Cancelando invitación…" : "Enviando invitación…", pending: true, tone: "neutral" });
    const result = existing?.status === "pending"
      ? await supabase.rpc("cancel_pachanga_match_invitation_v1", {
          client_metadata: marketOperationMetadata(),
          expected_invitation_revision: existing.revision,
          expected_match_revision: marketContext.revision,
          operation_id: crypto.randomUUID(),
          target_invitation_id: existing.id,
        })
      : await supabase.rpc("create_pachanga_match_invitation_v1", {
          client_metadata: marketOperationMetadata(),
          expected_revision: marketContext.revision,
          operation_id: crypto.randomUUID(),
          target_group_id: marketContext.groupId,
          target_market_profile_id: profile.id,
          target_match_id: marketContext.matchId,
        });
    if (result.error) {
      const safe = safeMarketError(result.error);
      setOperation(key, { message: safe.body, tone: "danger" });
      if (safe.stale) setMarketRefresh((value) => value + 1);
      return;
    }
    const payload = result.data as {
      confirmedRevision?: number;
      invitation?: { id?: string; revision?: number; status?: string; targetMarketProfileId?: string };
    } | null;
    const invitation = payload?.invitation;
    const status = invitation?.status === "accepted" || invitation?.status === "cancelled" || invitation?.status === "rejected" ? invitation.status : "pending";
    if (invitation?.id) {
      setMatchInvitations((current) => ({
        ...current,
        [profile.id]: {
          id: invitation.id as string,
          revision: Math.max(1, Math.floor(Number(invitation.revision) || 1)),
          status,
          targetMarketProfileId: invitation.targetMarketProfileId || profile.id,
        },
      }));
    }
    setMarketContext((current) => current ? {
      ...current,
      revision: Math.max(0, Math.floor(Number(payload?.confirmedRevision) || current.revision)),
    } : null);
    setOperation(key, { message: status === "cancelled" ? "Invitación cancelada." : status === "accepted" ? "Jugador confirmado." : "Invitación enviada.", tone: "success" });
  }

  async function respondIncomingInvitation(nextStatus: "accepted" | "rejected") {
    if (!online || !supabase || !incomingInvitation || incomingInvitationState === "responding") {
      setIncomingInvitationMessage("Necesitas conexión para confirmar esta acción.");
      return;
    }
    setIncomingInvitationState("responding");
    setIncomingInvitationMessage(nextStatus === "accepted" ? "Confirmando tu plaza…" : "Rechazando invitación…");
    const result = await supabase.rpc("respond_pachanga_match_invitation_v1", {
      client_metadata: marketOperationMetadata(),
      expected_invitation_revision: incomingInvitation.revision,
      expected_match_revision: incomingInvitation.matchRevision,
      next_status: nextStatus,
      operation_id: crypto.randomUUID(),
      target_invitation_id: incomingInvitation.invitationId,
    });
    if (result.error) {
      const safe = safeMarketError(result.error);
      setIncomingInvitationMessage(safe.body);
      setIncomingInvitationState("error");
      if (safe.stale) setIncomingInvitationRefresh((value) => value + 1);
      return;
    }
    setIncomingInvitationMessage(nextStatus === "accepted" ? "Invitación aceptada y confirmada por el servidor." : "Invitación rechazada.");
    setIncomingInvitationRefresh((value) => value + 1);
    setMarketRefresh((value) => value + 1);
  }

  const marketTabs: OfficialMarketTab[] = [
    { id: "partidos", label: "Partidos", onSelect: () => selectMarketTab("partidos") },
    { id: "jugadores", label: "Jugadores", onSelect: () => selectMarketTab("jugadores") },
    { id: "equipos", label: "Equipos", onSelect: () => selectMarketTab("equipos") },
  ];
  const subtitle = activeTab === "partidos"
    ? "Encuentra una pachanga y solicita tu plaza."
    : activeTab === "jugadores"
      ? "Busca a quien falta para completar el partido."
      : "Encuentra equipos de tu zona.";
  const activeSource = activeTab === "partidos" ? matchSource : activeTab === "jugadores" ? profileSource : teamSource;
  const resultCount = activeTab === "partidos" ? filteredMatches.length : activeTab === "jugadores" ? filteredProfiles.length : null;
  const resultPhase = resultCount === null ? null : marketQueryPhase(activeSource, resultCount, online);
  const confirmedResultCount = resultPhase === null ? null : visibleMarketResultCount(resultPhase, resultCount ?? 0);
  const resultNoun = activeTab === "partidos" ? "partidos" : activeTab === "jugadores" ? "jugadores" : "equipos";
  const sourceText = sourceLabel(activeSource, cacheUpdatedAt, online);
  const selectedRequest = selectedMatch ? openMatchRequests[selectedMatch.id] : undefined;
  const selectedInvitation = selectedPlayer ? matchInvitations[selectedPlayer.id] : undefined;

  return (
    <OfficialProductShellV2
      active="mercado"
      adminViewPreview={canInvite ? { active: playerPreviewActive, onToggle: toggleAdminViewPreview } : undefined}
      context={{ detail: "Partidos, jugadores y equipos", title: "Pachangas IQ" }}
    >
      <main className="market-page official-ui-v2-market" data-mobile-tab="mercado" data-market-source={activeSource}>
        <OfficialMarketGameView
          activeTab={activeTab}
          adminHref={canUseMarketAdminControls && marketContext?.matchUrl ? marketAdminMatchUrl(marketContext.matchUrl) : undefined}
          context={marketContext && activeTab === "jugadores" ? (
            <section className={styles.contextBand} aria-label="Partido usado para buscar jugadores">
              <div>
                <span>Buscando para</span>
                <strong>{marketContext.dateText || marketContext.title}</strong>
                <small>{[modalityLabels[marketContext.modality] || marketContext.modality, marketContext.zone, `${marketContext.missing || "0"} plazas libres`].filter(Boolean).join(" · ")}</small>
              </div>
              {marketContext.matchUrl ? <a href={marketContext.matchUrl}>Volver al partido</a> : null}
            </section>
          ) : undefined}
          search={(
            <div className={styles.searchStack}>
              <div className={styles.locationRow}>
                <label className={styles.locationField}>
                  <span className="sr-only">¿Dónde quieres jugar?</span>
                  <input
                    ref={zoneInputRef}
                    value={filters.zone}
                    onChange={(event) => {
                      const next = { ...filters, zone: event.target.value, zonePlaceId: undefined };
                      setFilters(next);
                      setFilterDraft(next);
                      setZonePlace(event.target.value ? { name: event.target.value } : null);
                    }}
                    onBlur={() => {
                      if (filters.zone && filters.zone !== "Mi ubicación aproximada") {
                        writeMarketLocationPreference(window.localStorage, { label: filters.zone, placeId: filters.zonePlaceId, radiusKm: filters.radiusKm });
                      }
                      replaceRoute({ filters });
                    }}
                    placeholder="¿Dónde quieres jugar?"
                  />
                  {locationMessage ? <small className={styles.locationHint} aria-live="polite">{locationMessage}</small> : null}
                </label>
                <button className={styles.locationAction} type="button" aria-label={locating ? "Buscando tu ubicación" : "Usar mi ubicación"} title="Usar mi ubicación" onClick={useMyLocation} disabled={locating}>
                  <LocationTargetIcon />
                  <span>{locating ? "Localizando…" : "Usar mi ubicación"}</span>
                </button>
                {filters.zone ? <button type="button" aria-label="Quitar ubicación" title="Quitar ubicación" onClick={() => applyQuickFilter({ zone: "", zonePlaceId: undefined })}>×</button> : null}
              </div>
              <div className={styles.quickRow} aria-label="Filtros rápidos">
                {MARKET_QUICK_DAYS.map((day) => (
                  <button key={day} type="button" aria-pressed={filters.day === day} onClick={() => applyQuickFilter({ day: filters.day === day ? "Todos" : day })}>{day}</button>
                ))}
                {Object.entries(modalityLabels).map(([value, label]) => (
                  <button key={value} type="button" aria-pressed={filters.modality === value} onClick={() => applyQuickFilter({ modality: filters.modality === value ? "Todas" : value })}>{label}</button>
                ))}
                <button className={styles.filterButton} type="button" aria-expanded={filtersOpen} onClick={() => {
                  setFilterDraft(filters);
                  setFiltersOpen(true);
                }}>Filtros</button>
              </div>
              {(filters.zone || filters.day !== "Todos" || filters.modality !== "Todas" || filters.position !== "Todas") ? (
                <div className={styles.activeFilters} aria-label="Filtros activos">
                  {filters.zone ? <button type="button" onClick={() => applyQuickFilter({ zone: "", zonePlaceId: undefined })}>{filters.zone} ×</button> : null}
                  {filters.day !== "Todos" ? <button type="button" onClick={() => applyQuickFilter({ day: "Todos" })}>{filters.day} ×</button> : null}
                  {filters.modality !== "Todas" ? <button type="button" onClick={() => applyQuickFilter({ modality: "Todas" })}>{modalityLabels[filters.modality] || filters.modality} ×</button> : null}
                  {filters.position !== "Todas" && activeTab !== "equipos" ? <button type="button" onClick={() => applyQuickFilter({ position: "Todas" })}>{filters.position} ×</button> : null}
                  <button className={styles.clearButton} type="button" onClick={clearFilters}>Limpiar</button>
                </div>
              ) : null}
            </div>
          )}
          status={(
            <div className={styles.headerActions}>
              <label className={styles.sortLabel}>
                <span>Ordenar por</span>
                <select value={filters.sort} onChange={(event) => applyQuickFilter({ sort: event.target.value as MarketSort })}>
                  <option value="relevance">Relevancia</option>
                  {activeTab === "partidos" ? <option value="date">Más próximo</option> : null}
                  {activeTab === "partidos" ? <option value="slots">Más plazas</option> : null}
                  {activeTab !== "partidos" ? <option value="level">Nivel</option> : null}
                  {Number.isFinite(activeTarget?.lat) ? <option value="distance">Más cerca</option> : null}
                </select>
              </label>
              <span className={styles.sourceBadge} data-source={activeSource}>{sourceText}</span>
            </div>
          )}
          subtitle={subtitle}
          tabs={marketTabs}
          title="Mercado"
        >
          {incomingInvitationId ? (
            <section className={styles.incomingInvitation} data-state={incomingInvitationState} aria-labelledby="incoming-match-invitation-title">
              <div>
                <span>Invitación de partido</span>
                <h2 id="incoming-match-invitation-title">{incomingInvitation?.matchTitle ?? (incomingInvitationState === "loading" ? "Cargando invitación…" : "Revisa tu invitación")}</h2>
                {incomingInvitation ? <p>{[incomingInvitation.teamName, incomingInvitation.matchDate, modalityLabels[incomingInvitation.matchKind] || incomingInvitation.matchKind, incomingInvitation.matchPlace].filter(Boolean).join(" · ")}</p> : null}
                {incomingInvitationMessage ? <small aria-live="polite">{incomingInvitationMessage}</small> : null}
              </div>
              <div>
                {incomingInvitationState === "signed-out" ? <a href={googleAuthEntryHref(`${typeof window === "undefined" ? "/mercado" : `${window.location.pathname}${window.location.search}`}`)}>Entrar para responder</a> : null}
                {incomingInvitation?.status === "pending" ? <><button disabled={!online || incomingInvitationState === "responding"} type="button" onClick={() => void respondIncomingInvitation("accepted")}>Aceptar</button><button disabled={!online || incomingInvitationState === "responding"} type="button" onClick={() => void respondIncomingInvitation("rejected")}>Rechazar</button></> : null}
                {incomingInvitation?.status === "accepted" ? <a href={`/?mobile=partido&p=${encodeURIComponent(incomingInvitation.matchId)}`}>Ver partido</a> : null}
                {incomingInvitation && incomingInvitation.status !== "pending" && incomingInvitation.status !== "accepted" ? <span>{incomingInvitation.status === "rejected" ? "Rechazada" : "Cancelada"}</span> : null}
              </div>
            </section>
          ) : null}
          {confirmedResultCount !== null ? (
            <div className={styles.resultsHeader}>
              <strong>{confirmedResultCount} {resultNoun} {confirmedResultCount === 1 ? "encontrado" : "encontrados"}</strong>
              {!online ? <span>Solo lectura sin conexión</span> : null}
            </div>
          ) : null}

          {activeTab === "partidos" ? (
            <div className={styles.resultsLayout} data-detail={Boolean(selectedMatch)}>
              <section className={styles.resultsColumn} aria-label="Partidos abiertos">
                {matchSource === "IDLE" && !openMatches.length ? (
                  <div className={styles.serviceState}>
                    <h2>Encuentra tu próximo partido</h2>
                    <p>Inicia sesión para buscar partidos abiertos. Conservaremos estos filtros cuando vuelvas.</p>
                    <div className={styles.emptyActions}>
                      <a className={styles.primaryButton} href={googleAuthEntryHref(`${typeof window === "undefined" ? "/mercado" : `${window.location.pathname}${window.location.search}`}`)}>Entrar para continuar</a>
                    </div>
                  </div>
                ) : matchSource === "LOADING" && !openMatches.length ? (
                  <div className={styles.serviceState}><h2>Buscando partidos</h2><p>Estamos cargando el estado confirmado del Mercado.</p></div>
                ) : matchSource === "UNAVAILABLE" && !openMatches.length ? (
                  <div className={styles.serviceState}>
                    <h2>{currentUserId ? "Partidos no disponibles" : "Entra para consultar partidos"}</h2>
                    <p>{currentUserId ? "No hemos podido recuperar los partidos y no hay una lectura guardada segura." : "Necesitas conexión para consultar partidos. Tus filtros se conservarán al entrar."}</p>
                    <div className={styles.emptyActions}>
                      {!currentUserId ? <a className={styles.primaryButton} href={googleAuthEntryHref(`${typeof window === "undefined" ? "/mercado" : `${window.location.pathname}${window.location.search}`}`)}>Entrar para continuar</a> : null}
                      <button className={styles.secondaryButton} type="button" onClick={() => setMarketRefresh((value) => value + 1)}>Reintentar</button>
                    </div>
                  </div>
                ) : filteredMatches.length ? (
                  <div className={styles.matchGrid}>
                    {filteredMatches.map((match) => {
                      const request = openMatchRequests[match.id];
                      const operation = operations[`match:${match.id}`];
                      const distance = distanceKmBetween(activeTarget, match.lat, match.lng);
                      const href = matchHrefFromRequest(request);
                      const selected = selectedMatch?.id === match.id;
                      return (
                        <article className={styles.matchCard} data-selected={selected} key={match.id}>
                          <header>
                            <div><span>{match.dateText}</span><strong>{match.groupName}</strong></div>
                            <b>{match.openSlots} plaza{match.openSlots === 1 ? "" : "s"}</b>
                          </header>
                          <p className={styles.matchMeta}>{[modalityLabels[match.modality] || match.modality, match.fieldName, match.zone, distance === null ? null : `≈ ${distance.toFixed(1)} km`].filter(Boolean).join(" · ")}</p>
                          <div className={styles.matchSummary}>
                            <span>{match.confirmedCount}/{match.targetPlayers} confirmados</span>
                            <span>{match.positions.length ? match.positions.join(" y ") : "Cualquier posición"}</span>
                            <span>{match.pricePerPlayer ? `${match.pricePerPlayer.toFixed(2)} €` : "Sin precio"}</span>
                            <span>{match.requiresApproval ? "Aprobación manual" : "Confirmación inmediata"}</span>
                          </div>
                          {request || operation ? (
                            <div className={styles.inlineState} data-tone={operation?.tone || (request?.status === "accepted" ? "success" : request?.status === "rejected" ? "danger" : "neutral")} aria-live="polite">
                              <strong>{request?.status === "accepted" ? "Plaza confirmada" : request?.status === "pending" ? "Solicitud enviada" : request?.status === "rejected" ? "No aceptada" : request?.status === "cancelled" ? "Solicitud cancelada" : operation?.pending ? "Confirmando" : "Estado"}</strong>
                              {operation?.message ? <small>{operation.message}</small> : null}
                            </div>
                          ) : null}
                          <footer className={styles.cardFooter}>
                            {request?.status !== "rejected" ? <button type="button" onClick={() => openDetail({ id: match.id, kind: "match" })}>Ver detalles</button> : null}
                            {request?.status === "accepted" && href ? <a href={href}>Ver partido</a>
                              : request?.status === "pending" ? href ? <a href={href}>Ver partido</a> : <button type="button" onClick={() => openDetail({ id: match.id, kind: "match" })}>Solicitud enviada</button>
                                : request?.status === "rejected" ? <button type="button" onClick={() => openDetail({ id: match.id, kind: "match" })}>Ver detalles</button>
                                  : <button type="button" disabled={operation?.pending || matchSource === "CACHED" || !online} onClick={() => void requestOpenMatch(match)}>{currentUserId ? request?.status === "cancelled" ? "Solicitar de nuevo" : "Solicitar plaza" : "Entrar para continuar"}</button>}
                          </footer>
                        </article>
                      );
                    })}
                  </div>
                ) : (
                  <div className={styles.emptyState}>
                    <h2>No hay partidos con estos filtros</h2>
                    <p>Prueba a ampliar el radio, cambiar el día o ver todas las modalidades.</p>
                    <div className={styles.emptyActions}><button className={styles.secondaryButton} type="button" onClick={() => applyQuickFilter({ radiusKm: Math.min(100, filters.radiusKm + 20) })}>Ampliar radio</button><button className={styles.primaryButton} type="button" onClick={clearFilters}>Ver todos</button></div>
                  </div>
                )}
              </section>
              {selectedMatch ? (
                <MarketDetailSheet label={`detalle de ${selectedMatch.groupName}`} onClose={closeDetail}>
                  <div className={styles.detailHero}><span>Partido abierto</span><h2>{selectedMatch.groupName}</h2><p>{selectedMatch.title}</p></div>
                  <dl className={styles.detailFacts}>
                    <div><dt>Fecha y hora</dt><dd>{selectedMatch.dateText}</dd></div>
                    <div><dt>Modalidad</dt><dd>{modalityLabels[selectedMatch.modality] || selectedMatch.modality}</dd></div>
                    <div><dt>Campo</dt><dd>{selectedMatch.fieldName}</dd></div>
                    <div><dt>Zona</dt><dd>{selectedMatch.zone}</dd></div>
                    <div><dt>Jugadores</dt><dd>{selectedMatch.confirmedCount}/{selectedMatch.targetPlayers}</dd></div>
                    <div><dt>Plazas</dt><dd>{selectedMatch.openSlots}</dd></div>
                    <div><dt>Posiciones</dt><dd>{selectedMatch.positions.join(", ") || "Cualquiera"}</dd></div>
                    <div><dt>Nivel orientativo</dt><dd>{overall(selectedMatch.minRating)}-{overall(selectedMatch.maxRating)}</dd></div>
                    <div><dt>Precio</dt><dd>{selectedMatch.pricePerPlayer ? `${selectedMatch.pricePerPlayer.toFixed(2)} € por jugador` : "Sin precio publicado"}</dd></div>
                    <div><dt>Aprobación</dt><dd>{selectedMatch.requiresApproval ? "Manual" : "Inmediata"}</dd></div>
                  </dl>
                  {operations[`match:${selectedMatch.id}`] ? <div className={styles.inlineState} data-tone={operations[`match:${selectedMatch.id}`].tone} aria-live="polite"><strong>Estado de la solicitud</strong><small>{operations[`match:${selectedMatch.id}`].message}</small></div> : null}
                  <div className={styles.detailActions}>
                    {selectedRequest?.status === "pending" ? <button type="button" disabled={!online} onClick={() => void cancelOpenMatchRequest(selectedRequest)}>Cancelar solicitud</button> : null}
                    {selectedRequest?.status === "accepted" && selectedRequest.actionUrl ? <a href={selectedRequest.actionUrl}>Ver partido</a>
                      : selectedRequest?.status !== "pending" && selectedRequest?.status !== "rejected" ? <button type="button" disabled={!online || matchSource === "CACHED"} onClick={() => void requestOpenMatch(selectedMatch)}>{selectedRequest?.status === "cancelled" ? "Solicitar de nuevo" : "Solicitar plaza"}</button> : null}
                  </div>
                </MarketDetailSheet>
              ) : null}
            </div>
          ) : activeTab === "jugadores" ? (
            <div className={styles.resultsLayout} data-detail={Boolean(selectedPlayer)}>
              <section className={styles.resultsColumn} aria-label="Jugadores del mercado">
                {profileSource === "LOADING" && !profiles.length ? (
                  <div className={styles.serviceState}><h2>Buscando jugadores</h2><p>Estamos cargando perfiles públicos confirmados.</p></div>
                ) : profileSource === "UNAVAILABLE" && !profiles.length ? (
                  <div className={styles.serviceState}><h2>Jugadores no disponibles</h2><p>No hay una lectura remota o guardada que podamos mostrar con seguridad.</p><button className={styles.primaryButton} type="button" onClick={() => setMarketRefresh((value) => value + 1)}>Reintentar</button></div>
                ) : filteredProfiles.length ? (
                  <div className={styles.playerGrid}>
                    {filteredProfiles.map((profile) => {
                      const invitation = matchInvitations[profile.id];
                      const operation = operations[`player:${profile.id}`];
                      const zone = profileZone(profile, activeTarget, filters.zone);
                      return (
                        <article className={styles.playerCard} data-selected={selectedPlayer?.id === profile.id} key={profile.id}>
                          <span className={styles.playerAvatar}>{profile.avatar ? <NextImage src={profile.avatar} alt="" width={58} height={58} loading="lazy" unoptimized style={avatarStyle(profile)} /> : profile.displayName.slice(0, 1)}</span>
                          <div>
                            <header><div><span>{profile.position}</span><strong>{profile.displayName}</strong></div><b>{overall(profile.media)}</b></header>
                            <div className={styles.playerMeta}>{profile.modalities.map((value) => <span key={value}>{modalityLabels[value] || value}</span>)}<span>{zone.distanceKm === null ? zone.label : `≈ ${zone.distanceKm.toFixed(1)} km`}</span></div>
                            <p className={styles.playerAvailability}>{profile.availabilityText || "Disponibilidad por confirmar"}</p>
                          </div>
                          {invitation || operation ? <div className={styles.inlineState} data-tone={operation?.tone || (invitation?.status === "accepted" ? "success" : "neutral")} aria-live="polite"><strong>{invitation?.status === "accepted" ? "Jugador confirmado" : invitation?.status === "pending" ? "Invitación enviada" : invitation?.status === "cancelled" ? "Invitación cancelada" : "Estado"}</strong>{operation?.message ? <small>{operation.message}</small> : null}</div> : null}
                          <footer className={styles.cardFooter}>
                            <button type="button" onClick={() => openDetail({ id: profile.id, kind: "player" })}>Ver perfil</button>
                            {marketContext && canUseMarketAdminControls ? <button type="button" disabled={!online || profileSource === "CACHED" || operation?.pending || invitation?.status === "pending" || invitation?.status === "accepted" || !profile.openToGuest} onClick={() => void toggleInvitation(profile)}>{invitation?.status === "accepted" ? "Confirmado" : invitation?.status === "pending" ? "Invitación enviada" : invitation?.status === "cancelled" ? "Invitar de nuevo" : "Invitar"}</button> : null}
                          </footer>
                        </article>
                      );
                    })}
                  </div>
                ) : (
                  <div className={styles.emptyState}><h2>No hay jugadores con estos filtros</h2><p>Cambia la posición, el día o amplía el radio sin perder tu zona.</p><div className={styles.emptyActions}><button className={styles.secondaryButton} type="button" onClick={() => applyQuickFilter({ position: "Todas" })}>Cualquier posición</button><button className={styles.primaryButton} type="button" onClick={clearFilters}>Ver todos</button></div></div>
                )}
              </section>
              {selectedPlayer ? (
                <MarketDetailSheet label={`perfil de ${selectedPlayer.displayName}`} onClose={closeDetail}>
                  <div className={styles.detailPlayerHero}>
                    <div className={styles.detailCardStage}><div className={styles.playerMiniCard}><b>{overall(selectedPlayer.media)}</b><strong>{selectedPlayer.displayName}</strong><span>{selectedPlayer.position}</span></div></div>
                    <div>
                      <div className={styles.detailHero}><span>Perfil de jugador</span><h2>{selectedPlayer.displayName}</h2><p>{selectedPlayer.bio || "Este jugador todavía no ha añadido una biografía pública."}</p></div>
                      <dl className={styles.detailFacts}>
                        <div><dt>Posición</dt><dd>{selectedPlayer.position}</dd></div>
                        <div><dt>Media</dt><dd>{overall(selectedPlayer.media)}</dd></div>
                        <div><dt>Modalidades</dt><dd>{selectedPlayer.modalities.map((value) => modalityLabels[value] || value).join(", ") || "Sin definir"}</dd></div>
                        <div><dt>Zonas</dt><dd>{selectedPlayer.zones.join(", ") || "Sin definir"}</dd></div>
                        <div><dt>Disponibilidad</dt><dd>{selectedPlayer.availabilityText || "Por confirmar"}</dd></div>
                        <div><dt>Partidos</dt><dd>{selectedPlayer.appearances}</dd></div>
                        <div><dt>Goles</dt><dd>{selectedPlayer.goals}</dd></div>
                        <div><dt>Victorias</dt><dd>{selectedPlayer.wins}</dd></div>
                      </dl>
                    </div>
                  </div>
                  {operations[`player:${selectedPlayer.id}`] ? <div className={styles.inlineState} data-tone={operations[`player:${selectedPlayer.id}`].tone} aria-live="polite"><strong>Estado de la invitación</strong><small>{operations[`player:${selectedPlayer.id}`].message}</small></div> : null}
                  <div className={styles.detailActions}>
                    {selectedInvitation?.status === "pending" ? <button type="button" disabled={!online} onClick={() => void toggleInvitation(selectedPlayer)}>Cancelar invitación</button> : null}
                    {marketContext && canUseMarketAdminControls && selectedInvitation?.status !== "pending" && selectedInvitation?.status !== "accepted" ? <button type="button" disabled={!online || !selectedPlayer.openToGuest} onClick={() => void toggleInvitation(selectedPlayer)}>{selectedInvitation?.status === "cancelled" ? "Invitar de nuevo" : "Invitar"}</button> : null}
                  </div>
                </MarketDetailSheet>
              ) : null}
            </div>
          ) : (
            <ChallengeableTeamsPanel
              marketFilters={filters}
              onCloseTeam={closeDetail}
              onOpenTeam={(teamId) => openDetail({ id: teamId, kind: "team" })}
              onPrepareChallenge={(team) => window.location.assign(`/retos?view=active&crear=1&rival=${encodeURIComponent(team.teamCode)}&returnTo=${encodeURIComponent(`${window.location.pathname}${window.location.search}`)}`)}
              onSourceChange={setTeamSource}
              selectedTeamId={selectedDetail?.kind === "team" ? selectedDetail.id : null}
            />
          )}
        </OfficialMarketGameView>
        {filtersOpen ? (
          <MarketFilterSheet
            activeTab={activeTab}
            draft={filterDraft}
            onApply={() => {
              setFilters(filterDraft);
              setFiltersOpen(false);
              pushRoute({ filters: filterDraft, tab: activeTab });
            }}
            onChange={(patch) => setFilterDraft((current) => ({ ...current, ...patch }))}
            onClose={() => setFiltersOpen(false)}
            onReset={() => setFilterDraft(createFilterDraft({ day: "Todos", maxPrice: null, maxRating: null, minRating: null, modality: "Todas", position: "Todas", radiusKm: 30, sort: "relevance", zone: "" }))}
            resultCount={draftResultCount}
          />
        ) : null}
      </main>
    </OfficialProductShellV2>
  );
}
