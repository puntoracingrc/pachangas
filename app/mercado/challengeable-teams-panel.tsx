"use client";

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
  onPrepareChallenge: (team: TeamSummary) => void;
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

export function ChallengeableTeamsPanel({ onPrepareChallenge }: Props) {
  const demoMode = typeof window !== "undefined"
    && new URLSearchParams(window.location.search).get("demo") === "1";
  const [memberships, setMemberships] = useState<GroupMembership[]>(() => demoMode ? [demoMembership] : []);
  const [selectedGroupId, setSelectedGroupId] = useState(() => demoMode ? demoMembership.groupId : "");
  const [currentUserId, setCurrentUserId] = useState(() => demoMode ? "demo-user" : "");
  const [profileSnapshot, setProfileSnapshot] = useState<ChallengeableTeamProfileSnapshot | null>(null);
  const [profileDraft, setProfileDraft] = useState<ChallengeableTeamProfile>(() => demoMode ? demoProfileDraft() : profileFromSnapshot(null));
  const [searchSnapshot, setSearchSnapshot] = useState<ChallengeableTeamSearchSnapshot | null>(
    () => demoMode ? demoSearchSnapshot(demoMembership.groupId) : null,
  );
  const [filters, setFilters] = useState<ChallengeableTeamSearchFilters>(defaultFilters);
  const [appliedFilters, setAppliedFilters] = useState<ChallengeableTeamSearchFilters>(defaultFilters);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(() => Boolean(supabase) && !demoMode);
  const [searching, setSearching] = useState(false);
  const [saving, setSaving] = useState(false);
  const [configOpen, setConfigOpen] = useState(false);
  const profileZoneInputRef = useRef<HTMLInputElement>(null);
  const searchZoneInputRef = useRef<HTMLInputElement>(null);
  const operationIdsRef = useRef(new Map<string, string>());

  const selectedMembership = useMemo(
    () => memberships.find((membership) => membership.groupId === selectedGroupId) ?? null,
    [memberships, selectedGroupId],
  );

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
      setMessage(result.error.message);
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
      return;
    }
    if (!supabase) return;
    if (useCache) {
      const cached = readChallengeableSearchCache(window.localStorage, userId, groupId, searchFilters, page);
      if (cached) setSearchSnapshot(cached);
    }
    if (!navigator.onLine) {
      setMessage("Sin conexión: se muestran solo resultados guardados, nunca como estado nuevo confirmado.");
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
      setMessage(result.error.message);
      return;
    }
    setMessage("");
    if (!acceptSearchSnapshot(result.data, userId, groupId, searchFilters, page)) {
      setMessage("El servidor no devolvió una página de equipos válida.");
    }
  }, [acceptSearchSnapshot, demoMode]);

  useEffect(() => {
    if (!supabase || demoMode) return;

    let active = true;
    async function loadGroups() {
      const session = await supabase?.auth.getSession();
      const user = session?.data.session?.user ?? null;
      if (!active) return;
      if (!user) {
        setMessage("Entra con Google para buscar o publicar equipos retables.");
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
        setMessage(result.error.message);
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
        await Promise.all([
          loadProfile(nextGroupId, user.id),
          loadSearch(nextGroupId, user.id, defaultFilters, 1),
        ]);
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
    if (!googleMapsApiKey || !searchZoneInputRef.current) return;
    let cleanup: (() => void) | undefined;
    let disposed = false;
    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input: searchZoneInputRef.current,
      onPlace: (place) => {
        if (disposed) return;
        const zone = zoneFromPlace(place);
        setFilters((current) => ({ ...current, zoneLabel: zone.label, zoneLat: zone.lat, zoneLng: zone.lng }));
        setMessage("");
      },
    }).then((nextCleanup) => {
      if (disposed) nextCleanup();
      else cleanup = nextCleanup;
    }).catch(() => setMessage("Puedes buscar por nombre de zona aunque Google Places no esté disponible."));
    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [loading]);

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
      setMessage(result.error.message);
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

  async function runSearch() {
    setAppliedFilters(filters);
    await loadSearch(selectedGroupId, currentUserId, filters, 1, false);
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
      setMessage(result.error.message);
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

  if (loading) return <section className="market-panel challengeable-teams-loading">Cargando equipos retables…</section>;
  if (!memberships.length) {
    return <section className="market-panel challengeable-teams-empty">Necesitas pertenecer a un equipo para buscar rivales.</section>;
  }

  return (
    <section className="challengeable-teams-area" aria-label="Equipos públicamente retables">
      <div className="challengeable-teams-toolbar">
        <label>
          Buscar como
          <select value={selectedGroupId} onChange={(event) => selectGroup(event.target.value)}>
            {memberships.map((membership) => <option key={membership.groupId} value={membership.groupId}>{membership.name}</option>)}
          </select>
        </label>
        <div>
          <span>Nivel del equipo</span>
          <strong>{profileSnapshot?.ownLevel !== null && profileSnapshot?.ownLevel !== undefined ? Math.round(profileSnapshot.ownLevel) : searchSnapshot?.requesterLevel !== null && searchSnapshot?.requesterLevel !== undefined ? Math.round(searchSnapshot.requesterLevel) : "Pendiente"}</strong>
        </div>
        <div>
          <span>Buscador</span>
          <strong>{searchSnapshot ? `Revisión ${searchSnapshot.searchRevision}` : "Sin snapshot"}</strong>
        </div>
        {(profileSnapshot?.canManage || demoMode) ? (
          <button type="button" onClick={() => setConfigOpen((current) => !current)} aria-expanded={configOpen}>
            {configOpen ? "Cerrar configuración" : "Configurar mi ficha"}
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

      <section className="market-panel challengeable-search-panel">
        <div className="challengeable-search-grid">
          <label className="challengeable-search-zone">
            Zona
            <input
              ref={searchZoneInputRef}
              value={filters.zoneLabel}
              onChange={(event) => setFilters((current) => ({ ...current, zoneLabel: event.target.value, zoneLat: null, zoneLng: null }))}
              placeholder="Ciudad o comarca"
            />
          </label>
          <label>
            Distancia
            <select value={filters.maxDistanceKm ?? 30} onChange={(event) => setFilters((current) => ({ ...current, maxDistanceKm: Number(event.target.value) }))}>
              {[5, 10, 20, 30, 50, 75, 100].map((radius) => <option key={radius} value={radius}>{radius} km</option>)}
            </select>
          </label>
          <label>
            Nivel desde
            <input type="number" min="0" max="100" placeholder="Todos" value={filters.minTeamLevel ?? ""} onChange={(event) => setFilters((current) => ({ ...current, minTeamLevel: event.target.value === "" ? null : Number(event.target.value) }))} />
          </label>
          <label>
            Nivel hasta
            <input type="number" min="0" max="100" placeholder="Todos" value={filters.maxTeamLevel ?? ""} onChange={(event) => setFilters((current) => ({ ...current, maxTeamLevel: event.target.value === "" ? null : Number(event.target.value) }))} />
          </label>
          <label>
            Día
            <select value={filters.day ?? ""} onChange={(event) => setFilters((current) => ({ ...current, day: event.target.value ? Number(event.target.value) : null }))}>
              <option value="">Cualquier día</option>
              {weekdays.map((day) => <option key={day} value={day}>{challengeableDayLabel(day)}</option>)}
            </select>
          </label>
          <label>
            Desde
            <input type="time" disabled={!filters.day} value={filters.start ?? ""} onChange={(event) => setFilters((current) => ({ ...current, start: event.target.value || null }))} />
          </label>
          <label>
            Hasta
            <input type="time" disabled={!filters.day} value={filters.end ?? ""} onChange={(event) => setFilters((current) => ({ ...current, end: event.target.value || null }))} />
          </label>
          <label>
            Modalidad
            <select value={filters.modality ?? ""} onChange={(event) => setFilters((current) => ({ ...current, modality: (event.target.value || null) as TeamChallengeModality | null }))}>
              <option value="">Todas</option>
              {modalities.map((value) => <option key={value} value={value}>{challengeableModalityLabel(value)}</option>)}
            </select>
          </label>
          <button className="challengeable-search-action" type="button" onClick={() => void runSearch()} disabled={searching}>{searching ? "Buscando…" : "Buscar equipos"}</button>
        </div>
      </section>

      {message ? <p className="challengeable-teams-message" aria-live="polite">{message}</p> : null}

      <div className="challengeable-results-heading">
        <div>
          <span>Equipos compatibles</span>
          <strong>{searchSnapshot?.items.length ?? 0}</strong>
        </div>
        <small>{searchSnapshot?.requesterLevel === null ? "Nivel propio pendiente: el rival decidirá la compatibilidad." : "Compatibilidad calculada por el servidor."}</small>
      </div>

      <section className="challengeable-team-grid" aria-label="Resultados de equipos retables">
        {searchSnapshot?.items.map((item) => (
          <article className="challengeable-team-card" key={item.groupId}>
            <header>
              <div><span>Equipo retable</span><strong>{item.name}</strong></div>
              <b>{item.teamLevel === null ? "Nivel -" : `Nivel ${Math.round(item.teamLevel)}`}</b>
            </header>
            <dl>
              <div><dt>Zona</dt><dd>{item.zoneLabel}</dd></div>
              <div><dt>Radio</dt><dd>{item.travelRadiusKm} km</dd></div>
              <div><dt>Rivales</dt><dd>{Math.round(item.minOpponentLevel)}-{Math.round(item.maxOpponentLevel)}</dd></div>
              {item.distanceKm !== null ? <div><dt>Distancia</dt><dd>≈ {item.distanceKm.toFixed(1)} km</dd></div> : null}
            </dl>
            <p>{availabilitySummary(item.availability) || "Disponibilidad por confirmar"}</p>
            <div className="challengeable-team-tags">
              {item.modalities.map((value) => <span key={value}>{challengeableModalityLabel(value)}</span>)}
              <span>{item.levelCompatibility === "compatible" ? "Nivel compatible" : "Compatibilidad pendiente"}</span>
            </div>
            <button type="button" onClick={() => void prepareChallenge(item)} disabled={selectedMembership?.role === "player"}>
              {selectedMembership?.role === "player" ? "Solo admins retan" : "Preparar reto"}
            </button>
          </article>
        ))}
        {!searchSnapshot?.items.length ? <p className="market-empty">No hay equipos públicos que encajen con estos filtros.</p> : null}
      </section>

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
