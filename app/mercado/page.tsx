"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { attachVenueAutocomplete, type VenuePlace } from "../googlePlacesClient";
import { MobileAppNav } from "../mobile-app-nav";
import { supabase } from "../supabaseClient";

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;

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

type MarketTarget = {
  lat?: number;
  lng?: number;
  name: string;
  placeId?: string;
};

type MarketProfile = {
  active: boolean;
  appearances: number;
  availabilityText: string;
  avatar?: string;
  avatarOffsetX?: number;
  avatarOffsetY?: number;
  bio: string;
  birthDate?: string;
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
  birth_date: string | null;
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
  fieldCost: number;
  fieldName: string;
  groupLevel: number | null;
  groupName: string;
  guestsPay: boolean;
  id: string;
  lat?: number;
  lng?: number;
  matchUrl: string;
  maxRating: number;
  minRating: number;
  modality: string;
  openSlots: number;
  placeId?: string;
  positions: string[];
  pricePerPlayer: number;
  requiresApproval: boolean;
  sourceMatchId: string;
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
  field_cost: number | string | null;
  field_name: string | null;
  group_level: number | string | null;
  group_name: string | null;
  guests_pay: boolean | null;
  id: string;
  lat: number | string | null;
  lng: number | string | null;
  match_url: string | null;
  max_media: number | string | null;
  min_media: number | string | null;
  modality: string | null;
  open_slots: number | string | null;
  place_id: string | null;
  positions: string[] | null;
  price_per_player: number | string | null;
  requires_approval: boolean | null;
  source_match_id: string | null;
  target_players: number | string | null;
  title: string | null;
  zone: string | null;
};

type OpenMatchRequestStatus = "accepted" | "cancelled" | "pending" | "rejected";

type OpenMatchRequestSummary = {
  openMatchId: string;
  status: OpenMatchRequestStatus;
};

type OpenMatchRequestSummaryRow = {
  open_match_id: string | null;
  status: string | null;
};

const fallbackProfiles: MarketProfile[] = [
  {
    active: true,
    appearances: 14,
    availabilityText: "Martes y jueves a partir de las 20:30",
    bio: "Delantero para completar partidos de fútbol 7 por la zona norte.",
    birthDate: "1988-04-12",
    displayName: "Carlos",
    goals: 18,
    goalkeeperOnly: false,
    groupName: "Demo Barcelona",
    id: "market-demo-1",
    media: 7.3,
    modalities: ["futbol7", "futbol11"],
    openToGroup: true,
    openToGuest: true,
    position: "Delantero / punta",
    wins: 7,
    zones: ["Barcelona", "Sabadell"],
    zonesGeo: [
      { city: "Barcelona", country: "España", lat: 41.3874, lng: 2.1686, name: "Barcelona", placeId: "demo-barcelona", province: "Barcelona", radiusKm: 25 },
      { city: "Sabadell", country: "España", lat: 41.5463, lng: 2.1086, name: "Sabadell", placeId: "demo-sabadell", province: "Barcelona", radiusKm: 15 },
    ],
  },
  {
    active: true,
    appearances: 9,
    availabilityText: "Miércoles noche y domingo mañana",
    bio: "Portero fijo. Puedo ir puntual si falta portería.",
    birthDate: "1981-09-22",
    displayName: "Rafa",
    goals: 1,
    goalkeeperOnly: true,
    groupName: "Demo Vallès",
    id: "market-demo-2",
    media: 6.3,
    modalities: ["sala", "futbol7"],
    openToGroup: false,
    openToGuest: true,
    position: "Portero",
    wins: 4,
    zones: ["Sabadell", "Terrassa"],
    zonesGeo: [
      { city: "Sabadell", country: "España", lat: 41.5463, lng: 2.1086, name: "Sabadell", placeId: "demo-sabadell-rafa", province: "Barcelona", radiusKm: 15 },
      { city: "Terrassa", country: "España", lat: 41.5632, lng: 2.0089, name: "Terrassa", placeId: "demo-terrassa", province: "Barcelona", radiusKm: 15 },
    ],
  },
  {
    active: true,
    appearances: 11,
    availabilityText: "Viernes 21:00 y sábados tarde",
    bio: "Medio organizador, mejor para fútbol 7.",
    birthDate: "1992-01-18",
    displayName: "Manu",
    goals: 10,
    goalkeeperOnly: false,
    groupName: "Demo Madrid",
    id: "market-demo-3",
    media: 6.9,
    modalities: ["futbol7"],
    openToGroup: true,
    openToGuest: true,
    position: "Mediocentro / pivote",
    wins: 8,
    zones: ["Madrid", "Alcobendas"],
    zonesGeo: [
      { city: "Madrid", country: "España", lat: 40.4168, lng: -3.7038, name: "Madrid", placeId: "demo-madrid", province: "Madrid", radiusKm: 20 },
      { city: "Alcobendas", country: "España", lat: 40.5373, lng: -3.6372, name: "Alcobendas", placeId: "demo-alcobendas", province: "Madrid", radiusKm: 15 },
    ],
  },
];

const fallbackOpenMatches: OpenMarketMatch[] = [
  {
    active: true,
    confirmedCount: 11,
    date: "2026-08-06T21:00",
    dateText: "jueves, 06 ago, 21:00",
    day: "Jueves",
    fieldCost: 56,
    fieldName: "Polideportivo La Mina",
    groupLevel: 6.4,
    groupName: "Demo Barcelona",
    guestsPay: true,
    id: "open-demo-1",
    lat: 41.4467,
    lng: 2.2146,
    matchUrl: "/",
    maxRating: 8,
    minRating: 5,
    modality: "futbol7",
    openSlots: 3,
    placeId: "demo-la-mina",
    positions: ["Defensa", "Medio"],
    pricePerPlayer: 4,
    requiresApproval: true,
    sourceMatchId: "demo-open-1",
    targetPlayers: 14,
    title: "Jueves 21:00",
    zone: "Sant Adrià de Besòs, Barcelona",
  },
  {
    active: true,
    confirmedCount: 8,
    date: "2026-08-08T19:30",
    dateText: "sábado, 08 ago, 19:30",
    day: "Sábado",
    fieldCost: 44,
    fieldName: "Pista municipal",
    groupLevel: 5.8,
    groupName: "Demo Vallès",
    guestsPay: false,
    id: "open-demo-2",
    lat: 41.5463,
    lng: 2.1086,
    matchUrl: "/",
    maxRating: 7,
    minRating: 4,
    modality: "sala",
    openSlots: 2,
    placeId: "demo-open-sabadell",
    positions: ["Portero", "Ataque"],
    pricePerPlayer: 0,
    requiresApproval: true,
    sourceMatchId: "demo-open-2",
    targetPlayers: 10,
    title: "Sala rápida",
    zone: "Sabadell, Barcelona",
  },
];

const dayFilters = ["Todos", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];
const modalityLabels: Record<string, string> = {
  futbol11: "Fútbol 11",
  futbol7: "Fútbol 7",
  sala: "Fútbol sala",
};
const positionFilters = ["Todas", "Portero", "Defensa", "Medio", "Ataque"];

type MarketMatchContext = {
  dateText: string;
  day: string;
  lat?: number;
  lng?: number;
  matchId: string;
  matchUrl: string;
  missing: string;
  modality: string;
  placeId?: string;
  title: string;
  zone: string;
};

function validDayFilter(value: string | null) {
  return value && dayFilters.includes(value) ? value : "Todos";
}

function validModalityFilter(value: string | null) {
  return value && (value === "Todas" || modalityLabels[value]) ? value : "Todas";
}

function numberParam(value: string | null) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : undefined;
}

function normalizeMarketZoneRadius(value: unknown) {
  const radius = Number(value);
  return [0, 5, 10, 20, 30, 50].includes(radius) ? radius : 0;
}

function normalizeMarketZone(zone: Partial<MarketZone> | null | undefined): MarketZone | null {
  const placeId = typeof zone?.placeId === "string" ? zone.placeId.trim() : "";
  const name = typeof zone?.name === "string" ? zone.name.trim() : "";
  if (!placeId || !name) return null;

  const lat = Number(zone?.lat);
  const lng = Number(zone?.lng);
  return {
    address: zone?.address || undefined,
    city: zone?.city || undefined,
    country: zone?.country || undefined,
    lat: Number.isFinite(lat) ? lat : undefined,
    lng: Number.isFinite(lng) ? lng : undefined,
    name,
    placeId,
    province: zone?.province || undefined,
    radiusKm: normalizeMarketZoneRadius(zone?.radiusKm),
  };
}

function normalizeMarketZonesGeo(value: unknown, legacyZones: string[] = []) {
  const rawZones = Array.isArray(value) ? value : [];
  const seen = new Set<string>();
  const zones: MarketZone[] = [];

  rawZones.forEach((zone) => {
    const normalized = normalizeMarketZone(zone as Partial<MarketZone>);
    if (!normalized || seen.has(normalized.placeId)) return;
    seen.add(normalized.placeId);
    zones.push(normalized);
  });

  if (zones.length) return zones.slice(0, 12);

  legacyZones.slice(0, 12).forEach((zone) => {
    const name = zone.trim();
    const legacyId = `legacy:${normalizeText(name)}`;
    if (!name || seen.has(legacyId)) return;
    seen.add(legacyId);
    zones.push({ name, placeId: legacyId, radiusKm: 0 });
  });

  return zones;
}

function marketZoneLabel(zone: Pick<MarketZone, "city" | "name" | "province">) {
  const main = zone.city || zone.name;
  const province = zone.province && normalizeText(zone.province) !== normalizeText(main) ? zone.province : "";
  return [main, province].filter(Boolean).join(", ");
}

function marketZoneRadiusLabel(radiusKm: number) {
  return radiusKm > 0 ? `+${radiusKm} km` : "solo ciudad";
}

function profileZoneListLabel(profile: MarketProfile) {
  const geoLabel = profile.zonesGeo
    .map((zone) => `${marketZoneLabel(zone)} · ${marketZoneRadiusLabel(zone.radiusKm)}`)
    .filter(Boolean)
    .join(" · ");
  return geoLabel || profile.zones.join(" · ");
}

function distanceKmBetween(origin: Pick<MarketZone, "lat" | "lng">, target: Pick<MarketTarget, "lat" | "lng">) {
  if (origin.lat === undefined || origin.lng === undefined || target.lat === undefined || target.lng === undefined) return null;
  const toRad = (value: number) => (value * Math.PI) / 180;
  const earthRadiusKm = 6371;
  const dLat = toRad(target.lat - origin.lat);
  const dLng = toRad(target.lng - origin.lng);
  const lat1 = toRad(origin.lat);
  const lat2 = toRad(target.lat);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 2 * earthRadiusKm * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function targetFromPlace(place: VenuePlace): MarketTarget {
  return {
    lat: place.lat,
    lng: place.lng,
    name: marketZoneLabel({ city: place.city, name: place.name, province: place.province }),
    placeId: place.placeId,
  };
}

function targetFromContext(context: MarketMatchContext | null): MarketTarget | null {
  if (!context?.zone) return null;
  return {
    lat: context.lat,
    lng: context.lng,
    name: context.zone,
    placeId: context.placeId,
  };
}

function activeMarketTarget(zonePlace: MarketTarget | null, context: MarketMatchContext | null, zoneQuery: string) {
  if (zonePlace) return zonePlace;
  const contextTarget = targetFromContext(context);
  if (!contextTarget || !zoneQuery.trim()) return null;
  return normalizeText(zoneQuery) === normalizeText(contextTarget.name) ? contextTarget : null;
}

function profileZoneMatch(profile: MarketProfile, target: MarketTarget | null, zoneQuery: string) {
  const query = zoneQuery.trim();
  if (!query && !target) return { label: profileZoneListLabel(profile), matches: true };

  if (target?.lat !== undefined && target.lng !== undefined) {
    const samePlace = target.placeId ? profile.zonesGeo.find((zone) => zone.placeId === target.placeId) : undefined;
    if (samePlace) {
      return {
        label: `${marketZoneLabel(samePlace)} · misma población · ${marketZoneRadiusLabel(samePlace.radiusKm)}`,
        matches: true,
      };
    }

    const candidates = profile.zonesGeo
      .map((zone) => ({ distance: distanceKmBetween(zone, target), zone }))
      .filter((entry): entry is { distance: number; zone: MarketZone } => entry.distance !== null)
      .sort((a, b) => a.distance - b.distance);

    const match = candidates.find((entry) => entry.distance <= entry.zone.radiusKm);
    if (match) {
      return {
        label: `${marketZoneLabel(match.zone)} · ${Math.round(match.distance)} km aprox. · ${marketZoneRadiusLabel(match.zone.radiusKm)}`,
        matches: true,
      };
    }

    if (candidates.length) {
      const closest = candidates[0];
      return {
        label: `${marketZoneLabel(closest.zone)} · ${Math.round(closest.distance)} km aprox. · fuera de radio`,
        matches: false,
      };
    }
  }

  const normalizedQuery = normalizeText(target?.name || query);
  const textMatchesZone =
    !normalizedQuery ||
    profile.zones.some((zone) => normalizeText(zone).includes(normalizedQuery) || normalizedQuery.includes(normalizeText(zone))) ||
    normalizeText(profile.groupName ?? "").includes(normalizedQuery);

  return {
    label: profileZoneListLabel(profile),
    matches: textMatchesZone,
  };
}

function normalizeRow(row: MarketRow): MarketProfile {
  const zones = row.zones ?? [];
  return {
    active: Boolean(row.active),
    appearances: Math.max(0, Math.floor(Number(row.appearances) || 0)),
    availabilityText: row.availability_text ?? "",
    avatar: row.avatar ?? undefined,
    avatarOffsetX: Number.isFinite(Number(row.avatar_offset_x)) ? Number(row.avatar_offset_x) : undefined,
    avatarOffsetY: Number.isFinite(Number(row.avatar_offset_y)) ? Number(row.avatar_offset_y) : undefined,
    bio: row.bio ?? "",
    birthDate: row.birth_date ?? undefined,
    displayName: row.display_name || "Jugador",
    goals: Math.max(0, Math.floor(Number(row.goals) || 0)),
    goalkeeperOnly: Boolean(row.goalkeeper_only),
    groupName: row.group_name ?? undefined,
    id: row.id,
    media: Math.max(1, Math.min(10, Number(row.media) || 5)),
    modalities: row.modalities ?? [],
    openToGroup: row.open_to_group ?? true,
    openToGuest: row.open_to_guest ?? true,
    position: row.position || "Mediocentro / pivote",
    wins: Math.max(0, Math.floor(Number(row.wins) || 0)),
    zones,
    zonesGeo: normalizeMarketZonesGeo(row.zones_geo, zones),
  };
}

function normalizeOpenMatchRow(row: OpenMarketMatchRow): OpenMarketMatch {
  return {
    active: Boolean(row.active),
    confirmedCount: Math.max(0, Math.floor(Number(row.confirmed_count) || 0)),
    date: row.date ?? "",
    dateText: row.date_text ?? "",
    day: row.day ?? "",
    fieldCost: Math.max(0, Number(row.field_cost) || 0),
    fieldName: row.field_name || "Campo por confirmar",
    groupLevel: Number.isFinite(Number(row.group_level)) ? Number(row.group_level) : null,
    groupName: row.group_name || "Grupo de pachangas",
    guestsPay: row.guests_pay ?? true,
    id: row.id,
    lat: Number.isFinite(Number(row.lat)) ? Number(row.lat) : undefined,
    lng: Number.isFinite(Number(row.lng)) ? Number(row.lng) : undefined,
    matchUrl: row.match_url ?? "",
    maxRating: Math.max(0, Math.min(10, Number(row.max_media) || 10)),
    minRating: Math.max(0, Math.min(10, Number(row.min_media) || 0)),
    modality: row.modality || "futbol7",
    openSlots: Math.max(0, Math.floor(Number(row.open_slots) || 0)),
    placeId: row.place_id ?? undefined,
    positions: row.positions ?? [],
    pricePerPlayer: Math.max(0, Number(row.price_per_player) || 0),
    requiresApproval: row.requires_approval ?? true,
    sourceMatchId: row.source_match_id || row.id,
    targetPlayers: Math.max(0, Math.floor(Number(row.target_players) || 0)),
    title: row.title || "Partido abierto",
    zone: row.zone || "",
  };
}

function openMatchZoneMatch(match: OpenMarketMatch, target: MarketTarget | null, zoneQuery: string) {
  const query = zoneQuery.trim();
  if (!query && !target) return { label: match.zone || match.fieldName, matches: true };

  if (target?.lat !== undefined && target.lng !== undefined && match.lat !== undefined && match.lng !== undefined) {
    if (target.placeId && match.placeId === target.placeId) {
      return { label: `${match.zone || match.fieldName} · misma zona`, matches: true };
    }
    const distance = distanceKmBetween({ lat: match.lat, lng: match.lng }, target);
    if (distance !== null) {
      return {
        label: `${match.zone || match.fieldName} · ${Math.round(distance)} km aprox.`,
        matches: distance <= 50,
      };
    }
  }

  const normalizedQuery = normalizeText(target?.name || query);
  const normalizedHaystack = normalizeText([match.zone, match.fieldName, match.groupName].filter(Boolean).join(" "));
  return {
    label: match.zone || match.fieldName,
    matches: !normalizedQuery || normalizedHaystack.includes(normalizedQuery) || normalizedQuery.includes(normalizedHaystack),
  };
}

function overall(media: number) {
  return Math.round(Math.max(1, Math.min(10, media)) * 10);
}

function levelOverall(media: number) {
  return Math.round(Math.max(0, Math.min(10, media)) * 10);
}

function normalizeText(value: string) {
  return value
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function normalizeBirthDate(value?: string) {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return "";
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(year, month - 1, day);
  if (parsed.getFullYear() !== year || parsed.getMonth() !== month - 1 || parsed.getDate() !== day) return "";
  return value;
}

function ageFromBirthDate(birthDate?: string) {
  const normalized = normalizeBirthDate(birthDate);
  if (!normalized) return null;
  const [birthYear, birthMonth, birthDay] = normalized.split("-").map(Number);
  const today = new Date();
  let age = today.getFullYear() - birthYear;
  if (today.getMonth() + 1 < birthMonth || (today.getMonth() + 1 === birthMonth && today.getDate() < birthDay)) age -= 1;
  return age >= 0 && age <= 120 ? age : null;
}

function cardTierClass(media: number) {
  const score = overall(media);
  if (score <= 64) return "fifa-card-bronze";
  if (score <= 74) return "fifa-card-silver";
  return "fifa-card-gold";
}

function positionShort(position: string, goalkeeperOnly: boolean) {
  if (goalkeeperOnly || position.toLowerCase().includes("portero")) return "POR";
  if (position.toLowerCase().includes("defensa") || position.toLowerCase().includes("cierre")) return "DEF";
  if (position.toLowerCase().includes("delantero") || position.toLowerCase().includes("pívot")) return "DEL";
  return "MC";
}

function avatarStyle(profile: MarketProfile) {
  return {
    objectPosition: `${Math.max(0, Math.min(100, profile.avatarOffsetX ?? 50))}% ${Math.max(0, Math.min(100, profile.avatarOffsetY ?? 0))}%`,
  };
}

function textMatches(value: string, query: string) {
  return normalizeText(value).includes(normalizeText(query));
}

function positionMatchesFilter(profile: MarketProfile, filter: string) {
  if (filter === "Todas") return true;
  const position = normalizeText(profile.position);
  if (filter === "Portero") return profile.goalkeeperOnly || position.includes("portero");
  if (filter === "Defensa") return position.includes("defensa") || position.includes("lateral") || position.includes("cierre") || position.includes("carrilero");
  if (filter === "Medio") return position.includes("medio") || position.includes("pivote defensivo") || position.includes("interior") || position.includes("volante") || position.includes("ala");
  if (filter === "Ataque") return position.includes("delantero") || position.includes("punta") || position.includes("extremo") || position.includes("pivot");
  return true;
}

function marketInviteText(profile: MarketProfile, context: MarketMatchContext) {
  return [
    `Hola ${profile.displayName}, ¿te apetece venir a este partido?`,
    context.title ? `Partido: ${context.title}` : "",
    context.dateText ? `Fecha: ${context.dateText}` : "",
    context.zone ? `Zona: ${context.zone}` : "",
    context.modality !== "Todas" ? `Modalidad: ${modalityLabels[context.modality] ?? context.modality}` : "",
    context.missing ? `Faltan: ${context.missing} plaza${context.missing === "1" ? "" : "s"}` : "",
    context.matchUrl ? `Enlace: ${context.matchUrl}` : "",
  ]
    .filter(Boolean)
    .join("\n");
}

export default function MarketPage() {
  const [profiles, setProfiles] = useState<MarketProfile[]>(fallbackProfiles);
  const [openMatches, setOpenMatches] = useState<OpenMarketMatch[]>(fallbackOpenMatches);
  const [openMatchRequests, setOpenMatchRequests] = useState<Record<string, OpenMatchRequestSummary>>({});
  const [activeTab, setActiveTab] = useState<"jugadores" | "partidos">("jugadores");
  const [zoneFilter, setZoneFilter] = useState("");
  const [dayFilter, setDayFilter] = useState("Todos");
  const [modalityFilter, setModalityFilter] = useState("Todas");
  const [positionFilter, setPositionFilter] = useState("Todas");
  const [canInvite, setCanInvite] = useState(false);
  const [inviteMessage, setInviteMessage] = useState("");
  const [marketContext, setMarketContext] = useState<MarketMatchContext | null>(null);
  const [zonePlace, setZonePlace] = useState<MarketTarget | null>(null);
  const [zonePlaceMessage, setZonePlaceMessage] = useState("");
  const zoneInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const tab = params.get("tab");
    if (tab === "partidos") setActiveTab("partidos");
    if (tab === "jugadores") setActiveTab("jugadores");
    const matchId = params.get("partido");
    if (!matchId) return;

    const nextDay = validDayFilter(params.get("dia"));
    const nextModality = validModalityFilter(params.get("modalidad"));
    const nextZone = params.get("zona") ?? "";
    const nextLat = numberParam(params.get("lat"));
    const nextLng = numberParam(params.get("lng"));
    const nextPlaceId = params.get("placeId") ?? undefined;

    setDayFilter(nextDay);
    setModalityFilter(nextModality);
    setZoneFilter(nextZone);
    setZonePlace(nextZone ? { lat: nextLat, lng: nextLng, name: nextZone, placeId: nextPlaceId } : null);
    setMarketContext({
      dateText: params.get("fecha") ?? "",
      day: nextDay,
      lat: nextLat,
      lng: nextLng,
      matchId,
      matchUrl: params.get("link") ?? "",
      missing: params.get("plazas") ?? "",
      modality: nextModality,
      placeId: nextPlaceId,
      title: params.get("titulo") ?? "Partido",
      zone: nextZone,
    });
  }, []);

  useEffect(() => {
    if (!supabase) return;
    let active = true;

    async function loadMarket() {
      const session = await supabase?.auth.getSession();
      const user = session?.data.session?.user ?? null;

      if (user) {
        const memberships = await supabase
          ?.from("pachanga_group_members")
          .select("role")
          .order("created_at", { ascending: true });
        if (active && !memberships?.error) {
          setCanInvite(Boolean((memberships?.data ?? []).some((membership) => ["owner", "admin"].includes(String(membership.role)))));
        }
      }

      const marketColumns =
        "id, display_name, avatar, avatar_offset_x, avatar_offset_y, birth_date, position, goalkeeper_only, media, appearances, goals, wins, zones, zones_geo, availability_text, modalities, open_to_guest, open_to_group, bio, active, group_name";
      const legacyMarketColumns =
        "id, display_name, avatar, avatar_offset_x, avatar_offset_y, birth_date, position, goalkeeper_only, media, appearances, goals, wins, zones, availability_text, modalities, open_to_guest, open_to_group, bio, active, group_name";
      let result = (await supabase
        ?.from("pachanga_market_profiles")
        .select(marketColumns)
        .eq("active", true)
        .order("media", { ascending: false })
        .limit(80)) as { data: unknown[] | null; error: { message: string } | null } | undefined;

      if (result?.error && result.error.message.includes("zones_geo")) {
        result = (await supabase
          ?.from("pachanga_market_profiles")
          .select(legacyMarketColumns)
          .eq("active", true)
          .order("media", { ascending: false })
          .limit(80)) as { data: unknown[] | null; error: { message: string } | null } | undefined;
      }

      if (!active) return;
      if (result?.error) {
        return;
      }

      const rows = (result?.data ?? []) as MarketRow[];
      setProfiles(rows.length ? rows.map(normalizeRow) : fallbackProfiles);

      const openMatchesResult = (await supabase
        ?.from("pachanga_open_matches")
        .select(
          "id, source_match_id, group_name, title, date, date_text, day, modality, zone, place_id, lat, lng, field_name, field_cost, price_per_player, target_players, confirmed_count, open_slots, min_media, max_media, positions, requires_approval, guests_pay, group_level, match_url, active",
        )
        .eq("active", true)
        .gt("open_slots", 0)
        .order("date", { ascending: true })
        .limit(80)) as { data: unknown[] | null; error: { message: string } | null } | undefined;

      if (!active) return;
      if (!openMatchesResult?.error) {
        const openRows = (openMatchesResult?.data ?? []) as OpenMarketMatchRow[];
        const nextOpenMatches = openRows.length ? openRows.map(normalizeOpenMatchRow) : fallbackOpenMatches;
        setOpenMatches(nextOpenMatches);

        if (user && nextOpenMatches.length) {
          const requestRows = (await supabase
            ?.from("pachanga_open_match_requests")
            .select("open_match_id, status")
            .in("open_match_id", nextOpenMatches.map((match) => match.id))
            .eq("requester_user_id", user.id)) as { data: unknown[] | null; error: { message: string } | null } | undefined;

          if (!requestRows?.error) {
            const nextRequests = ((requestRows?.data ?? []) as OpenMatchRequestSummaryRow[]).reduce<Record<string, OpenMatchRequestSummary>>((items, row) => {
              if (!row.open_match_id) return items;
              const status = row.status === "accepted" || row.status === "rejected" || row.status === "cancelled" ? row.status : "pending";
              items[row.open_match_id] = { openMatchId: row.open_match_id, status };
              return items;
            }, {});
            if (active) setOpenMatchRequests(nextRequests);
          }
        } else if (active) {
          setOpenMatchRequests({});
        }
      }
    }

    void loadMarket();

    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!googleMapsApiKey) {
      setZonePlaceMessage("Google Places pendiente.");
      return;
    }

    const input = zoneInputRef.current;
    if (!input) return;

    let cleanup: (() => void) | undefined;
    let disposed = false;

    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input,
      onPlace: (place) => {
        if (disposed) return;
        const nextTarget = targetFromPlace(place);
        setZoneFilter(nextTarget.name);
        setZonePlace(nextTarget);
        setZonePlaceMessage("");
      },
      types: ["(cities)"],
    })
      .then((nextCleanup) => {
        if (disposed) {
          nextCleanup();
          return;
        }
        cleanup = nextCleanup;
        setZonePlaceMessage("");
      })
      .catch((error: unknown) => {
        if (disposed) return;
        setZonePlaceMessage(error instanceof Error ? error.message : "No se pudo cargar Google Places.");
      });

    return () => {
      disposed = true;
      cleanup?.();
    };
  }, []);

  const filteredProfiles = useMemo(() => {
    const zoneQuery = zoneFilter.trim();
    const target = activeMarketTarget(zonePlace, marketContext, zoneQuery);

    return profiles.filter((profile) => {
      const zoneMatches = profileZoneMatch(profile, target, zoneQuery).matches;
      const dayMatches =
        dayFilter === "Todos" ||
        textMatches(profile.availabilityText, dayFilter) ||
        textMatches(profile.availabilityText, dayFilter.slice(0, 3));
      const modalityMatches = modalityFilter === "Todas" || profile.modalities.includes(modalityFilter);
      const positionMatches = positionMatchesFilter(profile, positionFilter);

      return zoneMatches && dayMatches && modalityMatches && positionMatches;
    });
  }, [dayFilter, marketContext, modalityFilter, positionFilter, profiles, zoneFilter, zonePlace]);

  const filteredOpenMatches = useMemo(() => {
    const zoneQuery = zoneFilter.trim();
    const target = activeMarketTarget(zonePlace, marketContext, zoneQuery);

    return openMatches.filter((match) => {
      const zoneMatches = openMatchZoneMatch(match, target, zoneQuery).matches;
      const dayMatches = dayFilter === "Todos" || match.day === dayFilter || textMatches(match.dateText, dayFilter);
      const modalityMatches = modalityFilter === "Todas" || match.modality === modalityFilter;
      const positionMatches = positionFilter === "Todas" || match.positions.length === 0 || match.positions.includes(positionFilter);

      return match.active && match.openSlots > 0 && zoneMatches && dayMatches && modalityMatches && positionMatches;
    });
  }, [dayFilter, marketContext, modalityFilter, openMatches, positionFilter, zoneFilter, zonePlace]);

  async function copyMarketInvite(profile: MarketProfile) {
    if (!marketContext || !profile.openToGuest) return;

    const text = marketInviteText(profile, marketContext);
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        setInviteMessage(`Invitación copiada para ${profile.displayName}.`);
        return;
      }
    } catch {
      // Fallback below.
    }

    window.prompt("Copia la invitación", text);
    setInviteMessage(`Invitación preparada para ${profile.displayName}.`);
  }

  async function requestOpenMatch(match: OpenMarketMatch) {
    if (!supabase) {
      setInviteMessage("Supabase no está configurado para enviar solicitudes.");
      return;
    }

    const session = await supabase.auth.getSession();
    if (!session.data.session?.user) {
      setInviteMessage("Entra con Google desde Pachangas IQ para poder solicitar plaza.");
      return;
    }

    const result = await supabase.rpc("request_pachanga_open_match", {
      operation_key: crypto.randomUUID(),
      target_open_match_id: match.id,
    });

    if (result.error) {
      setInviteMessage(result.error.message);
      return;
    }

    const status = (result.data as { status?: string } | null)?.status;
    const nextStatus: OpenMatchRequestStatus =
      status === "accepted" || status === "rejected" || status === "cancelled" ? status : "pending";
    setOpenMatchRequests((items) => ({
      ...items,
      [match.id]: { openMatchId: match.id, status: nextStatus },
    }));
    setInviteMessage(nextStatus === "accepted" ? "Plaza aceptada. Ya puedes entrar al partido." : `Solicitud enviada a ${match.groupName}.`);
  }

  return (
    <main className="market-page">
      <header className="market-titlebar">
        <div>
          <Link className="manual-back-button" href="/">Volver</Link>
          <h1>Mercado de fichajes</h1>
        </div>
      </header>

      {marketContext ? (
        <section className="market-panel market-context-panel" aria-label="Partido usado para buscar jugadores">
          <div>
            <span>Filtros aplicados desde el partido</span>
            <strong>{marketContext.title}</strong>
            <p>
              {[marketContext.dateText, marketContext.zone, modalityLabels[marketContext.modality] ?? marketContext.modality]
                .filter(Boolean)
                .join(" · ")}
            </p>
          </div>
          <div className="market-context-actions">
            <span>{marketContext.missing ? `${marketContext.missing} plaza${marketContext.missing === "1" ? "" : "s"} por cubrir` : "Partido seleccionado"}</span>
            {marketContext.matchUrl ? <a href={marketContext.matchUrl}>Volver al partido</a> : null}
          </div>
        </section>
      ) : null}

      <section className="market-panel market-filters" aria-label="Filtros del mercado de fichajes">
        <label>
          Zona
          <input
            ref={zoneInputRef}
            value={zoneFilter}
            onChange={(event) => {
              setZoneFilter(event.target.value);
              setZonePlace(null);
            }}
            placeholder="Busca ciudad con Google Places"
          />
          {zonePlaceMessage ? <small>{zonePlaceMessage}</small> : null}
        </label>
        <label>
          Día
          <select value={dayFilter} onChange={(event) => setDayFilter(event.target.value)}>
            {dayFilters.map((day) => (
              <option key={day} value={day}>{day}</option>
            ))}
          </select>
        </label>
        <label>
          Modalidad
          <select value={modalityFilter} onChange={(event) => setModalityFilter(event.target.value)}>
            <option value="Todas">Todas</option>
            {Object.entries(modalityLabels).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          Posición
          <select value={positionFilter} onChange={(event) => setPositionFilter(event.target.value)}>
            {positionFilters.map((position) => (
              <option key={position} value={position}>{position}</option>
            ))}
          </select>
        </label>
      </section>

      <div className="market-tabs" aria-label="Tipo de mercado">
        <button className={activeTab === "jugadores" ? "selected" : ""} type="button" onClick={() => setActiveTab("jugadores")}>
          Jugadores disponibles
        </button>
        <button className={activeTab === "partidos" ? "selected" : ""} type="button" onClick={() => setActiveTab("partidos")}>
          Partidos abiertos
        </button>
      </div>

      {activeTab === "jugadores" ? (
      <section className="market-grid" aria-label="Jugadores del mercado">
        {filteredProfiles.map((profile) => {
          const age = ageFromBirthDate(profile.birthDate);
          const zoneMatch = profileZoneMatch(profile, activeMarketTarget(zonePlace, marketContext, zoneFilter), zoneFilter);

          return (
          <article className="market-player" key={profile.id}>
            <div className={`fifa-player-card team-mini-player-card market-player-card ${cardTierClass(profile.media)}`}>
              <span className="fifa-score">{overall(profile.media)}</span>
              <span className="fifa-position">{positionShort(profile.position, profile.goalkeeperOnly)}</span>
              <span className="fifa-photo">
                {profile.avatar ? (
                  <img src={profile.avatar} alt="" draggable={false} style={avatarStyle(profile)} />
                ) : (
                  <b>+</b>
                )}
              </span>
              <strong>{profile.displayName}</strong>
              <span className="fifa-card-meta">{profile.goals} Goles · {profile.appearances} PJ{age !== null ? ` · ${age} años` : ""}</span>
              <div className="fifa-facets">
                <span><b>{profile.goals}</b>G</span>
                <span><b>{profile.appearances}</b>PJ</span>
                <span><b>{profile.wins}</b>PG</span>
              </div>
            </div>
            <div className="market-player-info">
              <span className="market-media-pill">Media {overall(profile.media)}</span>
              <strong>{profile.position}{age !== null ? ` · ${age} años` : ""}</strong>
              <small>{zoneMatch.label || (profile.zones.length ? profile.zones.join(" · ") : "Zona por definir")}</small>
              <small>{profile.availabilityText || "Disponibilidad por definir"}</small>
              <p>{profile.bio || "Ficha pública lista para completar pachangas."}</p>
              <div className="market-tags">
                {profile.modalities.map((modality) => (
                  <span key={modality}>{modalityLabels[modality] ?? modality}</span>
                ))}
                {profile.openToGuest ? <span>Invitado puntual</span> : null}
                {profile.openToGroup ? <span>Grupo</span> : null}
              </div>
              <button type="button" onClick={() => void copyMarketInvite(profile)} disabled={!canInvite || !marketContext || !profile.openToGuest}>
                {!canInvite ? "Solo admins invitan" : !marketContext ? "Invitar desde un partido" : !profile.openToGuest ? "No acepta puntual" : "Copiar invitación"}
              </button>
              {inviteMessage ? <small className="market-invite-message" aria-live="polite">{inviteMessage}</small> : null}
            </div>
          </article>
          );
        })}
        {filteredProfiles.length === 0 ? (
          <p className="market-empty">No hay jugadores que encajen con estos filtros todavía.</p>
        ) : null}
      </section>
      ) : (
      <section className="market-open-grid" aria-label="Partidos abiertos del mercado">
        {filteredOpenMatches.map((match) => {
          const zoneMatch = openMatchZoneMatch(match, activeMarketTarget(zonePlace, marketContext, zoneFilter), zoneFilter);
          const minOverall = levelOverall(match.minRating);
          const maxOverall = levelOverall(match.maxRating);
          const request = openMatchRequests[match.id];
          const requestStatus = request?.status;
          const requestPending = requestStatus === "pending";
          const requestAccepted = requestStatus === "accepted";
          const requestRejected = requestStatus === "rejected";

          return (
            <article className="market-open-match" key={match.id}>
              <div className="open-match-main">
                <span className="market-media-pill">{match.openSlots} plaza{match.openSlots === 1 ? "" : "s"}</span>
                <strong>{match.title}</strong>
                <p>{[match.dateText, zoneMatch.label, modalityLabels[match.modality] ?? match.modality].filter(Boolean).join(" · ")}</p>
                <div className="market-tags">
                  <span>Nivel {minOverall}-{maxOverall}</span>
                  {match.groupLevel !== null ? <span>Nivel equipo {overall(match.groupLevel)}</span> : null}
                  {match.positions.length ? match.positions.map((position) => <span key={position}>{position}</span>) : <span>Cualquier posición</span>}
                  <span>{match.guestsPay ? "Invitado paga" : "Invitado gratis"}</span>
                  <span>{match.requiresApproval ? "Admin acepta" : "Entrada directa"}</span>
                </div>
              </div>
              <div className="open-match-side">
                <span>{match.groupName}</span>
                <strong>{match.fieldName}</strong>
                <small>{match.confirmedCount}/{match.targetPlayers} confirmados</small>
                {match.pricePerPlayer > 0 ? <small>Referencia {match.pricePerPlayer.toFixed(2)} € por persona</small> : null}
                <button type="button" onClick={() => void requestOpenMatch(match)} disabled={requestPending || requestAccepted}>
                  {requestAccepted ? "Solicitud aceptada" : requestPending ? "Solicitud enviada" : requestRejected ? "Solicitar otra vez" : "Solicitar plaza"}
                </button>
                {requestAccepted && match.matchUrl ? <a href={match.matchUrl}>Ver partido</a> : null}
              </div>
            </article>
          );
        })}
        {filteredOpenMatches.length === 0 ? (
          <p className="market-empty">No hay partidos abiertos que encajen con estos filtros todavía.</p>
        ) : null}
      </section>
      )}
      <MobileAppNav
        active="mercado"
        links={{
          inicio: "/",
          partido: "/?mobile=partido",
          mercado: "/mercado",
          equipo: "/?mobile=equipo",
          perfil: "/?mobile=perfil",
        }}
      />
    </main>
  );
}
