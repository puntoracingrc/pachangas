"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  challengeableDayLabel,
  challengeableModalityLabel,
  normalizeChallengeableTeamProfileSnapshot,
  normalizeChallengeableTeamSearchSnapshot,
  readChallengeableProfileCache,
  readChallengeableSearchCache,
  type ChallengeableAvailabilitySlot,
  type ChallengeableTeamProfile,
  type ChallengeableTeamProfileSnapshot,
  type ChallengeableTeamSearchFilters,
  type ChallengeableTeamSearchItem,
  type ChallengeableTeamSearchSnapshot,
  writeChallengeableProfileCache,
  writeChallengeableSearchCache,
} from "../challengeable-team-contract";
import { attachVenueAutocomplete, type VenuePlace } from "../googlePlacesClient";
import { supabase } from "../supabaseClient";
import type { TeamChallengeModality, TeamSummary } from "../team-social-contract";
import { MarketDetailSheet } from "./market-detail-sheet";
import type { MarketFilterDraft } from "./market-filter-sheet";
import { safeMarketError } from "./market-ui-contract";
import styles from "./marketplace-v3d.module.css";

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
const weekdays = [1, 2, 3, 4, 5, 6, 7];
const modalities: TeamChallengeModality[] = ["sala", "futbol7", "futbol11"];

type GroupMembership = TeamSummary & {
  role: "admin" | "owner" | "player";
};

type SearchZone = {
  label: string;
  lat: number | null;
  lng: number | null;
  placeId: string | null;
};

type Props = {
  marketFilters: MarketFilterDraft;
  searchOrigin?: { lat?: number; lng?: number } | null;
  onCloseTeam: () => void;
  onOpenTeam: (teamId: string) => void;
  onPrepareChallenge: (team: TeamSummary) => void;
  onSourceChange?: (source: "CACHED" | "LIVE" | "LOADING" | "UNAVAILABLE") => void;
  selectedTeamId: string | null;
};

const emptySearchZone: SearchZone = { label: "", lat: null, lng: null, placeId: null };

const defaultProfile: ChallengeableTeamProfile = {
  availability: [{ day: 4, end: "22:30", start: "20:00" }],
  enabled: false,
  maxOpponentLevel: 100,
  minOpponentLevel: 0,
  modalities: ["futbol7"],
  travelRadiusKm: 20,
  zone: emptySearchZone,
};

const defaultFilters: ChallengeableTeamSearchFilters = {
  day: null,
  end: null,
  maxDistanceKm: 30,
  maxTeamLevel: null,
  minTeamLevel: null,
  modality: null,
  start: null,
  zoneLabel: "",
  zoneLat: null,
  zoneLng: null,
};

const demoMembership: GroupMembership = {
  groupId: "demo-search-team",
  name: "Pachangas IQ Demo",
  role: "owner",
  teamCode: "DEMOIQ",
};

function demoProfileDraft(): ChallengeableTeamProfile {
  return {
    ...defaultProfile,
    availability: defaultProfile.availability.map((slot) => ({ ...slot })),
    modalities: [...defaultProfile.modalities],
    zone: { label: "Barcelona", lat: 41.3874, lng: 2.1686, placeId: "demo-barcelona" },
  };
}

const demoItems: ChallengeableTeamSearchItem[] = [
  {
    availability: [{ day: 4, start: "20:00", end: "22:30" }, { day: 6, start: "18:00", end: "21:00" }],
    distanceKm: 4.8,
    groupId: "demo-public-team-1",
    levelCompatibility: "compatible",
    maxOpponentLevel: 78,
    minOpponentLevel: 52,
    modalities: ["futbol7"],
    name: "Atlètic Besòs",
    profileRevision: 4,
    teamLevel: 64,
    travelRadiusKm: 20,
    updatedAt: "2026-08-03T12:00:00.000Z",
    zoneLabel: "Sant Adrià de Besòs",
  },
  {
    availability: [{ day: 2, start: "20:30", end: "23:00" }, { day: 5, start: "20:30", end: "23:00" }],
    distanceKm: 11.2,
    groupId: "demo-public-team-2",
    levelCompatibility: "compatible",
    maxOpponentLevel: 82,
    minOpponentLevel: 58,
    modalities: ["futbol7", "futbol11"],
    name: "Barceloneta United",
    profileRevision: 2,
    teamLevel: 69,
    travelRadiusKm: 30,
    updatedAt: "2026-08-03T11:00:00.000Z",
    zoneLabel: "Barcelona litoral",
  },
  {
    availability: [{ day: 7, start: "10:00", end: "14:00" }],
    distanceKm: 18.6,
    groupId: "demo-public-team-3",
    levelCompatibility: "unknown",
    maxOpponentLevel: 70,
    minOpponentLevel: 35,
    modalities: ["sala"],
    name: "Vallès Sala",
    profileRevision: 7,
    teamLevel: 55,
    travelRadiusKm: 25,
    updatedAt: "2026-08-03T09:00:00.000Z",
    zoneLabel: "Sabadell y Vallès Occidental",
  },
];

function operationMetadata() {
  let sessionId = window.sessionStorage.getItem("pachangas-operation-session");
  if (!sessionId) {
    sessionId = crypto.randomUUID();
    window.sessionStorage.setItem("pachangas-operation-session", sessionId);
  }
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    sessionId,
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-market-public-teams" : "web-market-public-teams",
  };
}

function normalizeMemberships(value: unknown, userId: string): GroupMembership[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const row = item as Record<string, unknown>;
    if (row.user_id !== userId) return [];
    const nested = Array.isArray(row.pachanga_groups) ? row.pachanga_groups[0] : row.pachanga_groups;
    if (!nested || typeof nested !== "object") return [];
    const group = nested as Record<string, unknown>;
    const groupId = typeof group.id === "string" ? group.id : "";
    const name = typeof group.name === "string" ? group.name : "";
    const teamCode = typeof group.team_code === "string" ? group.team_code : "";
    if (!groupId || !name || seen.has(groupId)) return [];
    seen.add(groupId);
    const role = row.role === "owner" || row.role === "admin" ? row.role : "player";
    return [{ groupId, name, role, teamCode }];
  });
}

function profileFingerprint(profile: ChallengeableTeamProfile) {
  return JSON.stringify(profile);
}

function profileFromSnapshot(snapshot: ChallengeableTeamProfileSnapshot | null) {
  if (!snapshot) {
    return {
      ...defaultProfile,
      availability: defaultProfile.availability.map((slot) => ({ ...slot })),
      modalities: [...defaultProfile.modalities],
      zone: { ...defaultProfile.zone },
    };
  }
  return {
    ...snapshot.profile,
    availability: snapshot.profile.availability.length ? snapshot.profile.availability : defaultProfile.availability,
    modalities: snapshot.profile.modalities.length ? snapshot.profile.modalities : defaultProfile.modalities,
  };
}

function zoneFromPlace(place: VenuePlace): SearchZone {
  const label = [place.city || place.name, place.province].filter(Boolean).join(", ");
  return {
    label: label || place.name,
    lat: Number.isFinite(place.lat) ? place.lat ?? null : null,
    lng: Number.isFinite(place.lng) ? place.lng ?? null : null,
    placeId: place.placeId || null,
  };
}

function availabilitySummary(slots: ChallengeableAvailabilitySlot[]) {
  const grouped = new Map<string, string[]>();
  for (const slot of slots) {
    const label = `${slot.start}-${slot.end}`;
    const current = grouped.get(label) ?? [];
    current.push(challengeableDayLabel(slot.day).slice(0, 3));
    grouped.set(label, current);
  }
  return [...grouped.entries()].map(([hours, days]) => `${days.join(", ")} ${hours}`).join(" · ");
}

function weekdayFromMarketDay(day: MarketFilterDraft["day"]) {
  const labels = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"];
  if (day === "Hoy") return new Date().getDay() || 7;
  if (day === "Mañana") return ((new Date().getDay() + 1) % 7) || 7;
  const index = labels.indexOf(day);
  return index > 0 ? index : index === 0 ? 7 : null;
}

function demoSearchSnapshot(
  groupId: string,
  searchFilters: ChallengeableTeamSearchFilters = defaultFilters,
  page = 1,
): ChallengeableTeamSearchSnapshot {
  const zoneQuery = searchFilters.zoneLabel.trim().toLocaleLowerCase("es");
  const matchingItems = demoItems.filter((item) => {
    const levelMatches = item.teamLevel === null || (
      (searchFilters.minTeamLevel === null || item.teamLevel >= searchFilters.minTeamLevel)
      && (searchFilters.maxTeamLevel === null || item.teamLevel <= searchFilters.maxTeamLevel)
    );
    const zoneMatches = !zoneQuery || item.zoneLabel.toLocaleLowerCase("es").includes(zoneQuery);
    const distanceMatches = searchFilters.zoneLat === null
      || item.distanceKm === null
      || searchFilters.maxDistanceKm === null
      || item.distanceKm <= searchFilters.maxDistanceKm;
    const modalityMatches = searchFilters.modality === null || item.modalities.includes(searchFilters.modality);
    const availabilityMatches = searchFilters.day === null || item.availability.some((slot) => (
      slot.day === searchFilters.day
      && (
        !searchFilters.start
        || !searchFilters.end
        || (slot.start <= searchFilters.start && slot.end >= searchFilters.end)
      )
    ));
    return levelMatches && zoneMatches && distanceMatches && modalityMatches && availabilityMatches;
  });
  const pageSize = 12;
  const offset = (page - 1) * pageSize;
  return {
    confirmedRevision: 1,
    hasMore: offset + pageSize < matchingItems.length,
    items: matchingItems.slice(offset, offset + pageSize),
    page,
    pageSize,
    requesterLevel: 62,
    requestingGroupId: groupId,
    searchRevision: 1,
    serverSequence: 1,
    updatedAt: "2026-08-03T12:00:00.000Z",
  };
}

export function ChallengeableTeamsPanel({ marketFilters, searchOrigin, onCloseTeam, onOpenTeam, onPrepareChallenge, onSourceChange, selectedTeamId }: Props) {
  const searchLatitude = searchOrigin?.lat;
  const searchLongitude = searchOrigin?.lng;
  const demoMode = typeof window !== "undefined"
    && window.location.pathname.startsWith("/demo");
  const [memberships, setMemberships] = useState<GroupMembership[]>(() => demoMode ? [demoMembership] : []);
  const [selectedGroupId, setSelectedGroupId] = useState(() => demoMode ? demoMembership.groupId : "");
  const [currentUserId, setCurrentUserId] = useState(() => demoMode ? "demo-user" : "");
  const [profileSnapshot, setProfileSnapshot] = useState<ChallengeableTeamProfileSnapshot | null>(null);
  const [profileDraft, setProfileDraft] = useState<ChallengeableTeamProfile>(() => demoMode ? demoProfileDraft() : profileFromSnapshot(null));
  const [searchSnapshot, setSearchSnapshot] = useState<ChallengeableTeamSearchSnapshot | null>(
    () => demoMode ? demoSearchSnapshot(demoMembership.groupId) : null,
  );
  const [appliedFilters, setAppliedFilters] = useState<ChallengeableTeamSearchFilters>(defaultFilters);
  const [message, setMessage] = useState(() => !demoMode && !supabase ? "El catálogo de equipos no está disponible en este entorno." : "");
  const [loading, setLoading] = useState(() => Boolean(supabase) && !demoMode);
  const [searching, setSearching] = useState(false);
  const [saving, setSaving] = useState(false);
  const [configOpen, setConfigOpen] = useState(false);
  const [teamSource, setTeamSource] = useState<"CACHED" | "LIVE" | "LOADING" | "UNAVAILABLE">(() => demoMode ? "LIVE" : supabase ? "LOADING" : "UNAVAILABLE");
  const [online, setOnline] = useState(true);
  const profileZoneInputRef = useRef<HTMLInputElement>(null);
  const operationIdsRef = useRef(new Map<string, string>());

  const selectedMembership = useMemo(
    () => memberships.find((membership) => membership.groupId === selectedGroupId) ?? null,
    [memberships, selectedGroupId],
  );

  const selectedTeam = useMemo(
    () => searchSnapshot?.items.find((item) => item.groupId === selectedTeamId) ?? null,
    [searchSnapshot?.items, selectedTeamId],
  );

  useEffect(() => {
    onSourceChange?.(teamSource);
  }, [onSourceChange, teamSource]);

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

  const operationIdFor = useCallback((fingerprint: string) => {
    const existing = operationIdsRef.current.get(fingerprint);
    if (existing) return existing;
    const next = crypto.randomUUID();
    operationIdsRef.current.set(fingerprint, next);
    return next;
  }, []);

  const acceptProfileSnapshot = useCallback((value: unknown, userId: string, groupId: string) => {
    const canonical = normalizeChallengeableTeamProfileSnapshot(value);
    if (!canonical || canonical.group.groupId !== groupId) return false;
    setProfileSnapshot(canonical);
    setProfileDraft(profileFromSnapshot(canonical));
    try {
      writeChallengeableProfileCache(window.localStorage, userId, groupId, canonical);
    } catch {
      // The server snapshot remains authoritative if browser storage is unavailable.
    }
    return true;
  }, []);

  const acceptSearchSnapshot = useCallback((
    value: unknown,
    userId: string,
    groupId: string,
    searchFilters: ChallengeableTeamSearchFilters,
    page: number,
  ) => {
    const canonical = normalizeChallengeableTeamSearchSnapshot(value);
    if (!canonical || canonical.requestingGroupId !== groupId || canonical.page !== page) return false;
    setSearchSnapshot(canonical);
    try {
      writeChallengeableSearchCache(window.localStorage, userId, groupId, searchFilters, page, canonical);
    } catch {
      // Cached search results are optional read acceleration only.
    }
    return true;
  }, []);

  const loadProfile = useCallback(async (groupId: string, userId: string) => {
    if (!supabase || !groupId) return;
    const result = await supabase.rpc("get_pachanga_challengeable_team_profile", { target_group_id: groupId });
    if (result.error) {
      setMessage(safeMarketError(result.error).body);
      return;
    }
    if (!acceptProfileSnapshot(result.data, userId, groupId)) {
      setMessage("El servidor no devolvió una configuración pública válida.");
    }
  }, [acceptProfileSnapshot]);

  const loadSearch = useCallback(async (
    groupId: string,
    userId: string,
    searchFilters: ChallengeableTeamSearchFilters,
    page: number,
    useCache = true,
  ) => {
    if (!groupId) return;
    if (demoMode) {
      setSearchSnapshot(demoSearchSnapshot(groupId, searchFilters, page));
      setTeamSource("LIVE");
      return;
    }
    if (!supabase) return;
    if (useCache) {
      const cached = readChallengeableSearchCache(window.localStorage, userId, groupId, searchFilters, page);
      if (cached) {
        setSearchSnapshot(cached);
        setTeamSource("CACHED");
      }
    }
    if (!navigator.onLine) {
      setMessage("Sin conexión: se muestran solo resultados guardados, nunca como estado nuevo confirmado.");
      setTeamSource((current) => current === "CACHED" ? current : "UNAVAILABLE");
      return;
    }
    setSearching(true);
    const result = await supabase.rpc("search_pachanga_challengeable_teams", {
      requesting_group_id: groupId,
      target_end_time: searchFilters.day && searchFilters.start && searchFilters.end ? searchFilters.end : null,
      target_max_distance_km: searchFilters.zoneLat !== null ? searchFilters.maxDistanceKm : null,
      target_max_team_level: searchFilters.maxTeamLevel,
      target_min_team_level: searchFilters.minTeamLevel,
      target_modality: searchFilters.modality,
      target_page: page,
      target_page_size: 12,
      target_start_time: searchFilters.day && searchFilters.start && searchFilters.end ? searchFilters.start : null,
      target_weekday: searchFilters.day,
      target_zone_lat: searchFilters.zoneLat,
      target_zone_lng: searchFilters.zoneLng,
      target_zone_query: searchFilters.zoneLat === null ? searchFilters.zoneLabel.trim() || null : null,
    });
    setSearching(false);
    if (result.error) {
      setMessage(safeMarketError(result.error).body);
      setTeamSource((current) => current === "CACHED" ? current : "UNAVAILABLE");
      return;
    }
    setMessage("");
    if (!acceptSearchSnapshot(result.data, userId, groupId, searchFilters, page)) {
      setMessage("El servidor no devolvió una página de equipos válida.");
      setTeamSource("UNAVAILABLE");
    } else {
      setTeamSource("LIVE");
    }
  }, [acceptSearchSnapshot, demoMode]);

  useEffect(() => {
    const nextFilters: ChallengeableTeamSearchFilters = {
      day: weekdayFromMarketDay(marketFilters.day),
      end: null,
      maxDistanceKm: marketFilters.radiusKm,
      maxTeamLevel: marketFilters.maxRating,
      minTeamLevel: marketFilters.minRating,
      modality: marketFilters.modality === "Todas" ? null : marketFilters.modality as TeamChallengeModality,
      start: null,
      zoneLabel: marketFilters.zone,
      zoneLat: typeof searchLatitude === "number" && Number.isFinite(searchLatitude) ? searchLatitude : null,
      zoneLng: typeof searchLongitude === "number" && Number.isFinite(searchLongitude) ? searchLongitude : null,
    };
    window.queueMicrotask(() => {
      setAppliedFilters(nextFilters);
      if (selectedGroupId && currentUserId) void loadSearch(selectedGroupId, currentUserId, nextFilters, 1, true);
    });
  }, [
    currentUserId,
    loadSearch,
    marketFilters.day,
    marketFilters.maxRating,
    marketFilters.minRating,
    marketFilters.modality,
    marketFilters.radiusKm,
    marketFilters.zone,
    searchLatitude,
    searchLongitude,
    selectedGroupId,
  ]);

  useEffect(() => {
    if (demoMode || !supabase) return;

    let active = true;
    async function loadGroups() {
      const session = await supabase?.auth.getSession();
      const user = session?.data.session?.user ?? null;
      if (!active) return;
      if (!user) {
        setMessage("Entra para buscar equipos con la autoridad actual. Tus filtros se conservarán.");
        setTeamSource("UNAVAILABLE");
        setLoading(false);
        return;
      }

      setCurrentUserId(user.id);
      const result = await supabase
        ?.from("pachanga_group_members")
        .select("group_id, user_id, role, pachanga_groups(id, name, team_code)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: true });
      if (!active) return;
      if (result?.error) {
        setMessage(safeMarketError(result.error).body);
        setTeamSource("UNAVAILABLE");
        setLoading(false);
        return;
      }

      const nextMemberships = normalizeMemberships(result?.data, user.id);
      setMemberships(nextMemberships);
      const preferredGroupId = window.localStorage.getItem("pachangas-social-selected-group") ?? "";
      const nextGroupId = nextMemberships.some((group) => group.groupId === preferredGroupId)
        ? preferredGroupId
        : nextMemberships[0]?.groupId ?? "";
      setSelectedGroupId(nextGroupId);
      if (nextGroupId) {
        const cachedProfile = readChallengeableProfileCache(window.localStorage, user.id, nextGroupId);
        if (cachedProfile) {
          setProfileSnapshot(cachedProfile);
          setProfileDraft(profileFromSnapshot(cachedProfile));
        }
        // Search is driven by the current filters and origin in the effect above.
        await loadProfile(nextGroupId, user.id);
      } else {
        setTeamSource("UNAVAILABLE");
      }
      if (active) setLoading(false);
    }

    void loadGroups();
    return () => {
      active = false;
    };
  }, [demoMode, loadProfile, loadSearch]);

  function selectGroup(groupId: string) {
    if (!groupId || !currentUserId) return;
    setSelectedGroupId(groupId);
    window.localStorage.setItem("pachangas-social-selected-group", groupId);
    const cachedProfile = readChallengeableProfileCache(window.localStorage, currentUserId, groupId);
    setProfileSnapshot(cachedProfile);
    setProfileDraft(profileFromSnapshot(cachedProfile));
    const cachedSearch = readChallengeableSearchCache(window.localStorage, currentUserId, groupId, appliedFilters, 1);
    setSearchSnapshot(cachedSearch);
    void Promise.all([
      loadProfile(groupId, currentUserId),
      loadSearch(groupId, currentUserId, appliedFilters, 1),
    ]);
  }

  useEffect(() => {
    if (!supabase || !selectedGroupId || demoMode) return;
    const profileChannel = supabase
      .channel(`pachanga-challengeable-profile-${selectedGroupId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_challengeable_team_profile_state", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadProfile(selectedGroupId, currentUserId),
      )
      .subscribe();
    const searchChannel = supabase
      .channel("pachanga-challengeable-search")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_challengeable_team_search_state", filter: "id=eq.true" },
        () => void loadSearch(selectedGroupId, currentUserId, appliedFilters, searchSnapshot?.page ?? 1, false),
      )
      .subscribe();
    return () => {
      void supabase?.removeChannel(profileChannel);
      void supabase?.removeChannel(searchChannel);
    };
  }, [appliedFilters, currentUserId, demoMode, loadProfile, loadSearch, searchSnapshot?.page, selectedGroupId]);

  useEffect(() => {
    if (!supabase || !selectedGroupId || demoMode) return;
    const refresh = () => {
      if (!navigator.onLine) return;
      void Promise.all([
        loadProfile(selectedGroupId, currentUserId),
        loadSearch(selectedGroupId, currentUserId, appliedFilters, searchSnapshot?.page ?? 1, false),
      ]);
    };
    const refreshVisible = () => {
      if (document.visibilityState === "visible") refresh();
    };
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", refreshVisible);
    return () => {
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", refreshVisible);
    };
  }, [appliedFilters, currentUserId, demoMode, loadProfile, loadSearch, searchSnapshot?.page, selectedGroupId]);

  useEffect(() => {
    if (!googleMapsApiKey || !profileZoneInputRef.current || !configOpen || (!profileSnapshot?.canManage && !demoMode)) return;
    let cleanup: (() => void) | undefined;
    let disposed = false;
    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input: profileZoneInputRef.current,
      onPlace: (place) => {
        if (disposed) return;
        setProfileDraft((current) => ({ ...current, zone: zoneFromPlace(place) }));
        setMessage("");
      },
    }).then((nextCleanup) => {
      if (disposed) nextCleanup();
      else cleanup = nextCleanup;
    }).catch(() => setMessage("Selecciona una zona con coordenadas antes de activar la ficha."));
    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [configOpen, demoMode, profileSnapshot?.canManage]);

  async function saveProfile() {
    if (demoMode) {
      setMessage("La demo no guarda cambios. En un equipo real el servidor confirmará esta configuración.");
      return;
    }
    if (!supabase || !profileSnapshot || !navigator.onLine) {
      setMessage("Conéctate para guardar. La ficha local no se considerará confirmada.");
      return;
    }
    if (profileDraft.enabled && (
      !profileDraft.zone.label.trim()
      || profileDraft.zone.lat === null
      || profileDraft.zone.lng === null
      || !profileDraft.modalities.length
      || !profileDraft.availability.length
    )) {
      setMessage("Para activar la ficha elige zona, modalidad y al menos una franja.");
      return;
    }

    const fingerprint = `challengeable-profile:${selectedGroupId}:${profileSnapshot.profileRevision}:${profileFingerprint(profileDraft)}`;
    const operationId = operationIdFor(fingerprint);
    setSaving(true);
    setMessage("");
    const result = await supabase.rpc("upsert_pachanga_challengeable_team_profile_authoritative", {
      client_metadata: operationMetadata(),
      expected_revision: profileSnapshot.profileRevision,
      operation_id: operationId,
      target_availability: profileDraft.availability,
      target_enabled: profileDraft.enabled,
      target_group_id: selectedGroupId,
      target_max_opponent_level: profileDraft.maxOpponentLevel,
      target_min_opponent_level: profileDraft.minOpponentLevel,
      target_modalities: profileDraft.modalities,
      target_travel_radius_km: profileDraft.travelRadiusKm,
      target_zone_label: profileDraft.zone.label.trim() || null,
      target_zone_lat: profileDraft.zone.lat,
      target_zone_lng: profileDraft.zone.lng,
      target_zone_place_id: profileDraft.zone.placeId,
    });
    setSaving(false);
    if (result.error) {
      setMessage(safeMarketError(result.error).body);
      if (result.error.code === "PT409") await loadProfile(selectedGroupId, currentUserId);
      return;
    }
    operationIdsRef.current.delete(fingerprint);
    if (!acceptProfileSnapshot(result.data, currentUserId, selectedGroupId)) {
      setMessage("El servidor confirmó la operación, pero la ficha recibida no era válida. Recargando.");
      await loadProfile(selectedGroupId, currentUserId);
      return;
    }
    setMessage(profileDraft.enabled ? "Ficha pública guardada y confirmada." : "Ficha pública desactivada y confirmada.");
    await loadSearch(selectedGroupId, currentUserId, appliedFilters, 1, false);
  }

  async function prepareChallenge(item: ChallengeableTeamSearchItem) {
    if (demoMode) {
      setMessage("En la demo puedes explorar la ficha. En uso real este botón prepara un reto confirmado por servidor.");
      return;
    }
    if (!supabase || !navigator.onLine) {
      setMessage("Conéctate para preparar el reto.");
      return;
    }
    const result = await supabase.rpc("lookup_pachanga_challengeable_team_for_challenge", {
      opponent_group_id: item.groupId,
      requesting_group_id: selectedGroupId,
    });
    if (result.error) {
      setMessage(safeMarketError(result.error).body);
      await loadSearch(selectedGroupId, currentUserId, appliedFilters, searchSnapshot?.page ?? 1, false);
      return;
    }
    const value = result.data as Partial<TeamSummary> | null;
    if (!value?.groupId || !value.name || !value.teamCode) {
      setMessage("El servidor no devolvió un rival público válido.");
      return;
    }
    onPrepareChallenge({ groupId: value.groupId, name: value.name, teamCode: value.teamCode });
  }

  function toggleModality(value: TeamChallengeModality) {
    setProfileDraft((current) => ({
      ...current,
      modalities: current.modalities.includes(value)
        ? current.modalities.filter((item) => item !== value)
        : [...current.modalities, value],
    }));
  }

  function updateSlot(index: number, patch: Partial<ChallengeableAvailabilitySlot>) {
    setProfileDraft((current) => ({
      ...current,
      availability: current.availability.map((slot, slotIndex) => slotIndex === index ? { ...slot, ...patch } : slot),
    }));
  }

  if (loading) return <section className={styles.serviceState}><h2>Buscando equipos</h2><p>Estamos cargando el catálogo canónico del Mercado.</p></section>;
  if (!memberships.length) {
    return (
      <section className={styles.serviceState}>
        <h2>Necesitas un equipo para enviar retos</h2>
        <p>La autoridad actual permite consultar rivales desde un equipo registrado. No hemos sustituido esa restricción por datos ficticios.</p>
        <div className={styles.emptyActions}>
          <Link className={styles.primaryButton} href="/?mobile=inicio&create=team">Crear equipo</Link>
          <Link className={styles.secondaryButton} href="/?mobile=perfil&settings=1">Unirme a un equipo</Link>
        </div>
      </section>
    );
  }

  return (
    <section className="challengeable-teams-area" aria-label="Equipos públicamente retables">
      <div className={styles.resultsHeader}>
        <label>
          Buscar como
          <select value={selectedGroupId} onChange={(event) => selectGroup(event.target.value)}>
            {memberships.map((membership) => <option key={membership.groupId} value={membership.groupId}>{membership.name}</option>)}
          </select>
        </label>
        <span>{teamSource === "CACHED" ? "Resultados guardados · solo lectura" : teamSource === "UNAVAILABLE" ? "Servicio no disponible" : `${searchSnapshot?.items.length ?? 0} equipos encontrados`}</span>
        {(profileSnapshot?.canManage || demoMode) ? (
          <button type="button" onClick={() => setConfigOpen((current) => !current)} aria-expanded={configOpen}>
            {configOpen ? "Cerrar" : "Mi equipo en Mercado"}
          </button>
        ) : null}
      </div>

      {configOpen && (profileSnapshot?.canManage || demoMode) ? (
        <section className="market-panel challengeable-profile-editor">
          <header>
            <div>
              <span>Ficha pública voluntaria</span>
              <strong>{selectedMembership?.name}</strong>
            </div>
            <label className="challengeable-enabled-toggle">
              <input
                type="checkbox"
                checked={profileDraft.enabled}
                onChange={(event) => setProfileDraft((current) => ({ ...current, enabled: event.target.checked }))}
              />
              <span>{profileDraft.enabled ? "Disponible" : "Oculta"}</span>
            </label>
          </header>

          <div className="challengeable-profile-grid">
            <label className="challengeable-zone-field">
              Zona pública
              <input
                ref={profileZoneInputRef}
                value={profileDraft.zone.label}
                onChange={(event) => setProfileDraft((current) => ({
                  ...current,
                  zone: { label: event.target.value, lat: null, lng: null, placeId: null },
                }))}
                placeholder="Ciudad o comarca, nunca dirección habitual"
              />
            </label>
            <label>
              Radio
              <select value={profileDraft.travelRadiusKm} onChange={(event) => setProfileDraft((current) => ({ ...current, travelRadiusKm: Number(event.target.value) }))}>
                {[5, 10, 20, 30, 50, 75, 100].map((radius) => <option key={radius} value={radius}>{radius} km</option>)}
              </select>
            </label>
            <label>
              Rival mínimo
              <input type="number" min="0" max="100" value={profileDraft.minOpponentLevel} onChange={(event) => setProfileDraft((current) => ({ ...current, minOpponentLevel: Number(event.target.value) }))} />
            </label>
            <label>
              Rival máximo
              <input type="number" min="0" max="100" value={profileDraft.maxOpponentLevel} onChange={(event) => setProfileDraft((current) => ({ ...current, maxOpponentLevel: Number(event.target.value) }))} />
            </label>
          </div>

          <fieldset className="challengeable-modalities">
            <legend>Modalidades</legend>
            {modalities.map((value) => (
              <label key={value}>
                <input type="checkbox" checked={profileDraft.modalities.includes(value)} onChange={() => toggleModality(value)} />
                <span>{challengeableModalityLabel(value)}</span>
              </label>
            ))}
          </fieldset>

          <div className="challengeable-slots">
            <header><span>Días y franjas</span><button type="button" onClick={() => setProfileDraft((current) => ({ ...current, availability: [...current.availability, { day: 4, start: "20:00", end: "22:00" }] }))}>Añadir franja</button></header>
            {profileDraft.availability.map((slot, index) => (
              <div className="challengeable-slot-row" key={`${index}-${slot.day}-${slot.start}`}>
                <select aria-label="Día" value={slot.day} onChange={(event) => updateSlot(index, { day: Number(event.target.value) })}>
                  {weekdays.map((day) => <option key={day} value={day}>{challengeableDayLabel(day)}</option>)}
                </select>
                <input aria-label="Inicio" type="time" value={slot.start} onChange={(event) => updateSlot(index, { start: event.target.value })} />
                <input aria-label="Fin" type="time" value={slot.end} onChange={(event) => updateSlot(index, { end: event.target.value })} />
                <button type="button" aria-label="Eliminar franja" title="Eliminar franja" onClick={() => setProfileDraft((current) => ({ ...current, availability: current.availability.filter((_, slotIndex) => slotIndex !== index) }))}>×</button>
              </div>
            ))}
          </div>

          <div className="challengeable-editor-footer">
            <p>La ficha muestra solo zona aproximada, nivel y disponibilidad. El campo exacto se comparte dentro del reto.</p>
            <button type="button" onClick={() => void saveProfile()} disabled={saving}>{saving ? "Guardando…" : demoMode ? "Probar guardado" : "Guardar ficha"}</button>
          </div>
        </section>
      ) : null}

      {message ? <p className="challengeable-teams-message" aria-live="polite">{message}</p> : null}

      <div className={styles.resultsLayout} data-detail={Boolean(selectedTeam)}>
        <section className={styles.resultsColumn} aria-label="Resultados de equipos retables">
          {teamSource === "UNAVAILABLE" && !searchSnapshot?.items.length ? (
            <div className={styles.serviceState}><h2>Equipos no disponibles</h2><p>No hay una lectura remota o guardada que podamos mostrar con seguridad.</p></div>
          ) : searchSnapshot?.items.length ? (
            <div className={styles.matchGrid}>
              {searchSnapshot.items.map((item) => (
                <article className={styles.matchCard} data-selected={selectedTeam?.groupId === item.groupId} key={item.groupId}>
                  <header>
                    <div><span>{item.zoneLabel}</span><strong>{item.name}</strong></div>
                    <b>{item.teamLevel === null ? "Nivel -" : Math.round(item.teamLevel)}</b>
                  </header>
                  <p className={styles.matchMeta}>{[item.modalities.map(challengeableModalityLabel).join(" · "), item.distanceKm === null ? null : `≈ ${item.distanceKm.toFixed(1)} km`, availabilitySummary(item.availability)].filter(Boolean).join(" · ")}</p>
                  <div className={styles.matchSummary}>
                    <span>{item.levelCompatibility === "compatible" ? "Nivel compatible" : "Compatibilidad pendiente"}</span>
                    <span>Radio {item.travelRadiusKm} km</span>
                  </div>
                  <footer className={styles.cardFooter}>
                    <button type="button" onClick={() => onOpenTeam(item.groupId)}>Ver equipo</button>
                    {selectedMembership?.role !== "player" ? <button type="button" disabled={!online || teamSource === "CACHED"} onClick={() => void prepareChallenge(item)}>Retar</button> : null}
                  </footer>
                </article>
              ))}
            </div>
          ) : (
            <div className={styles.emptyState}><h2>No hay equipos con estos filtros</h2><p>Amplía el radio o cambia modalidad y nivel desde Filtros.</p></div>
          )}
        </section>
        {selectedTeam ? (
          <MarketDetailSheet label={`equipo ${selectedTeam.name}`} onClose={onCloseTeam}>
            <div className={styles.detailHero}><span>Equipo disponible</span><h2>{selectedTeam.name}</h2><p>{availabilitySummary(selectedTeam.availability) || "Disponibilidad por confirmar"}</p></div>
            <dl className={styles.detailFacts}>
              <div><dt>Nivel</dt><dd>{selectedTeam.teamLevel === null ? "Pendiente" : Math.round(selectedTeam.teamLevel)}</dd></div>
              <div><dt>Zona</dt><dd>{selectedTeam.zoneLabel}</dd></div>
              <div><dt>Distancia</dt><dd>{selectedTeam.distanceKm === null ? "No calculada" : `≈ ${selectedTeam.distanceKm.toFixed(1)} km`}</dd></div>
              <div><dt>Modalidades</dt><dd>{selectedTeam.modalities.map(challengeableModalityLabel).join(", ")}</dd></div>
              <div><dt>Rivales</dt><dd>{Math.round(selectedTeam.minOpponentLevel)}-{Math.round(selectedTeam.maxOpponentLevel)}</dd></div>
              <div><dt>Compatibilidad</dt><dd>{selectedTeam.levelCompatibility === "compatible" ? "Compatible" : "Pendiente"}</dd></div>
            </dl>
            <div className={styles.detailActions}>
              {selectedMembership?.role === "player" ? <span>Solo owner o admin puede enviar el reto.</span> : <button type="button" disabled={!online || teamSource === "CACHED"} onClick={() => void prepareChallenge(selectedTeam)}>Retar</button>}
            </div>
          </MarketDetailSheet>
        ) : null}
      </div>

      {searchSnapshot ? (
        <nav className="challengeable-pagination" aria-label="Páginas de equipos">
          <button
            type="button"
            disabled={searchSnapshot.page <= 1 || searching}
            onClick={() => void loadSearch(selectedGroupId, currentUserId, appliedFilters, searchSnapshot.page - 1, false)}
          >
            Anterior
          </button>
          <span>Página {searchSnapshot.page}</span>
          <button
            type="button"
            disabled={!searchSnapshot.hasMore || searching}
            onClick={() => void loadSearch(selectedGroupId, currentUserId, appliedFilters, searchSnapshot.page + 1, false)}
          >
            Siguiente
          </button>
        </nav>
      ) : null}
    </section>
  );
}
