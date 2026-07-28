"use client";

import { CSSProperties, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "./supabaseClient";

type Player = {
  id: string;
  name: string;
  avatar?: string;
  phone?: string;
  goalkeeperOnly?: boolean;
  rating: number;
  ratings?: number[];
  position: "Porteria" | "Defensa" | "Medio" | "Ataque";
  goals: number;
  assists: number;
  appearances: number;
  wins: number;
  lateCancels: number;
};

type MatchPlayer = {
  playerId: string;
  status: "voy" | "duda" | "no";
  joinedAt?: string;
  paid?: boolean;
};

type MatchKind = "sala" | "futbol7" | "futbol11";

type Venue = {
  id: string;
  name: string;
  defaultCost: number;
  kind?: MatchKind;
};

type SiteSettings = {
  brand: string;
  title: string;
  subtitle: string;
  teamAColor: string;
  teamBColor: string;
};

type Match = {
  id: string;
  title: string;
  date: string;
  place: string;
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
  scoreA?: number;
  scoreB?: number;
  teamA?: string[];
  teamB?: string[];
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
  id: string;
  inviteToken: string;
  name: string;
  payload: AppPayload;
  role: MemberRole;
  teamCode: string;
};

type RemoteMember = {
  displayName: string;
  role: MemberRole;
  userId: string;
};

const seedPlayers: Player[] = [
  { id: "p1", name: "Carlos", phone: "600 111 222", rating: 8, position: "Ataque", goals: 18, assists: 7, appearances: 12, wins: 7, lateCancels: 1 },
  { id: "p2", name: "Manu", phone: "600 222 333", rating: 7, position: "Medio", goals: 10, assists: 13, appearances: 11, wins: 8, lateCancels: 0 },
  { id: "p3", name: "Pablo", phone: "600 333 444", rating: 6, position: "Defensa", goals: 5, assists: 4, appearances: 10, wins: 5, lateCancels: 2 },
  { id: "p4", name: "Rafa", phone: "600 444 555", rating: 7, position: "Porteria", goals: 1, assists: 2, appearances: 9, wins: 4, lateCancels: 0 },
  { id: "p5", name: "Dani", phone: "600 555 666", rating: 5, position: "Medio", goals: 6, assists: 3, appearances: 8, wins: 3, lateCancels: 1 },
  { id: "p6", name: "Alex", phone: "600 666 777", rating: 6, position: "Defensa", goals: 4, assists: 8, appearances: 9, wins: 6, lateCancels: 0 },
  { id: "p7", name: "Sergio", phone: "600 777 888", rating: 8, position: "Ataque", goals: 15, assists: 5, appearances: 8, wins: 5, lateCancels: 1 },
  { id: "p8", name: "Javi", phone: "600 888 999", rating: 5, position: "Defensa", goals: 3, assists: 6, appearances: 7, wins: 2, lateCancels: 3 },
];

const seedVenues: Venue[] = [
  { id: "v1", name: "Polideportivo La Mina", defaultCost: 56, kind: "futbol7" },
  { id: "v2", name: "Pista El Parque", defaultCost: 42, kind: "sala" },
  { id: "v3", name: "Municipal Norte", defaultCost: 110, kind: "futbol11" },
];

const seedMatches: Match[] = [
  {
    id: "m1",
    title: "Jueves 21:00",
    date: "2026-07-30T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    payerId: "p1",
    players: [],
  },
];

const storageKey = "pachanga-iq-v1";
const profileNameKey = "pachanga-iq-profile-name";

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
  brand: "Pachanga IQ",
  title: "El grupo del partido, pero con memoria.",
  subtitle: "Confirma gente, guarda resultados y monta equipos equilibrados sin discutir media hora en WhatsApp.",
  teamAColor: "#2157a8",
  teamBColor: "#d93025",
};

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

const matchKinds: Record<MatchKind, { label: string; targetPlayers: number; teamSize: number }> = {
  sala: { label: "Fútbol sala", targetPlayers: 10, teamSize: 5 },
  futbol7: { label: "Fútbol 7", targetPlayers: 14, teamSize: 7 },
  futbol11: { label: "Fútbol 11", targetPlayers: 22, teamSize: 11 },
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

function scorePlayer(player: Player) {
  return peerAverage(player);
}

function displayName(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .map((word) => word.charAt(0).toLocaleUpperCase("es-ES") + word.slice(1).toLocaleLowerCase("es-ES"))
    .join(" ");
}

function playerDisplayName(player: Player) {
  return displayName(player.name);
}

function normalizeSiteSettings(settings?: Partial<SiteSettings>): SiteSettings {
  return {
    ...defaultSiteSettings,
    ...settings,
    teamAColor: settings?.teamAColor ?? defaultSiteSettings.teamAColor,
    teamBColor: settings?.teamBColor ?? defaultSiteSettings.teamBColor,
  };
}

function normalizePayload(payload?: Partial<AppPayload>): AppPayload {
  const fallback = defaultPayload();
  const venues = payload?.venues?.length ? payload.venues : fallback.venues;
  const matches = payload?.matches?.length
    ? payload.matches.map((match) => ({
        ...match,
        venueId: match.venueId ?? venues.find((venue) => venue.name === match.place)?.id,
        fieldCost: match.fieldCost ?? (match.price ? match.price * Math.max(match.targetPlayers, 1) : 0),
        lineupClosed: match.lineupClosed ?? false,
        reservesAttend: match.reservesAttend ?? false,
        reserveLimit: Math.max(0, Math.floor(match.reserveLimit ?? 0)),
      }))
    : fallback.matches;

  return {
    activeMatchId: payload?.activeMatchId && matches.some((match) => match.id === payload.activeMatchId) ? payload.activeMatchId : matches[0].id,
    matches,
    players: payload?.players ?? fallback.players,
    siteSettings: normalizeSiteSettings(payload?.siteSettings),
    venues,
  };
}

function peerAverage(player: Player) {
  if (!player.ratings?.length) return player.rating;
  return player.ratings.reduce((sum, rating) => sum + rating, 0) / player.ratings.length;
}

function playerPosition(player: Player): Player["position"] {
  return player.goalkeeperOnly ? "Porteria" : player.position;
}

function positionRank(player: Player) {
  const order: Record<Player["position"], number> = { Porteria: 0, Defensa: 1, Medio: 2, Ataque: 3 };
  return order[playerPosition(player)];
}

function sortedLineupPlayers(players: Player[]) {
  return [...players].sort((a, b) => positionRank(a) - positionRank(b) || scorePlayer(b) - scorePlayer(a) || a.name.localeCompare(b.name, "es"));
}

function positionLabel(player: Player) {
  const position = playerPosition(player);
  if (position === "Medio") return "Medio / lateral";
  if (position === "Ataque") return "Delantero / punta";
  return position;
}

function balanceTeams(players: Player[]) {
  const ordered = [...players].sort((a, b) => scorePlayer(b) - scorePlayer(a));
  const teamA: Player[] = [];
  const teamB: Player[] = [];

  ordered.forEach((player) => {
    const totalA = teamA.reduce((sum, item) => sum + scorePlayer(item), 0);
    const totalB = teamB.reduce((sum, item) => sum + scorePlayer(item), 0);
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

export default function Home() {
  const [players, setPlayers] = useState<Player[]>(seedPlayers);
  const [venues, setVenues] = useState<Venue[]>(seedVenues);
  const [matches, setMatches] = useState<Match[]>(seedMatches);
  const [activeMatchId, setActiveMatchId] = useState(seedMatches[0].id);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [newPlayer, setNewPlayer] = useState("");
  const [newVenue, setNewVenue] = useState({ name: "", cost: "56", kind: "futbol7" as MatchKind });
  const [newRating, setNewRating] = useState("5");
  const [openQuickForm, setOpenQuickForm] = useState<"player" | "venue" | "team" | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [siteSettings, setSiteSettings] = useState<SiteSettings>(defaultSiteSettings);
  const [result, setResult] = useState({ a: "", b: "" });
  const [remoteGroupId, setRemoteGroupId] = useState<string | null>(null);
  const [remoteInviteToken, setRemoteInviteToken] = useState<string | null>(null);
  const [remoteReady, setRemoteReady] = useState(false);
  const [syncStatus, setSyncStatus] = useState<"connecting" | "error" | "live" | "local">("local");
  const [syncError, setSyncError] = useState("");
  const [remoteTeams, setRemoteTeams] = useState<RemoteTeam[]>([]);
  const [teamMembers, setTeamMembers] = useState<RemoteMember[]>([]);
  const [currentRole, setCurrentRole] = useState<MemberRole | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [profileName, setProfileName] = useState("");
  const [newTeamName, setNewTeamName] = useState("Mi equipo pachanguero");
  const [localHydrated, setLocalHydrated] = useState(false);
  const applyingRemoteRef = useRef(false);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playerProfileRef = useRef<HTMLDivElement>(null);

  function currentPayload(): AppPayload {
    return {
      activeMatchId,
      matches,
      players,
      siteSettings,
      venues,
    };
  }

  function applyPayload(payload: AppPayload) {
    applyingRemoteRef.current = true;
    setPlayers(payload.players);
    setVenues(payload.venues);
    setSiteSettings(payload.siteSettings);
    setMatches(payload.matches);
    setActiveMatchId(payload.activeMatchId);
    window.setTimeout(() => {
      applyingRemoteRef.current = false;
    }, 0);
  }

  async function ensureUser(client: NonNullable<typeof supabase>) {
    const sessionResult = await client.auth.getSession();
    const existingUserId = sessionResult.data.session?.user.id;
    if (existingUserId) {
      setCurrentUserId(existingUserId);
      return existingUserId;
    }

    const signInResult = await client.auth.signInAnonymously();
    if (signInResult.error || !signInResult.data.user) {
      throw new Error(signInResult.error?.message ?? "No se pudo crear usuario anonimo");
    }

    setCurrentUserId(signInResult.data.user.id);
    return signInResult.data.user.id;
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
  }

  async function loadTeams(client: NonNullable<typeof supabase>, preferredGroupId?: string | null) {
    const memberships = await client
      .from("pachanga_group_members")
      .select("group_id, role, pachanga_groups(id, name, team_code, invite_token, payload)")
      .order("created_at", { ascending: true });

    if (memberships.error) throw new Error(memberships.error.message);

    const teams = (memberships.data ?? [])
      .map((membership) => {
        const group = Array.isArray(membership.pachanga_groups)
          ? membership.pachanga_groups[0]
          : membership.pachanga_groups;
        if (!group) return null;

        return {
          id: String(group.id),
          inviteToken: String(group.invite_token),
          name: String(group.name ?? "Equipo pachanguero"),
          payload: normalizePayload(group.payload as Partial<AppPayload>),
          role: (membership.role as MemberRole | null) ?? "player",
          teamCode: String(group.team_code ?? group.id).toUpperCase(),
        } satisfies RemoteTeam;
      })
      .filter((team): team is RemoteTeam => Boolean(team));

    setRemoteTeams(teams);

    const selectedTeam = teams.find((team) => team.id === preferredGroupId) ?? teams[0];
    if (!selectedTeam) {
      setRemoteGroupId(null);
      setRemoteInviteToken(null);
      setCurrentRole(null);
      setTeamMembers([]);
      setRemoteReady(false);
      setSyncStatus("local");
      return;
    }

    setRemoteGroupId(selectedTeam.id);
    setRemoteInviteToken(selectedTeam.inviteToken);
    setCurrentRole(selectedTeam.role);
    applyPayload(selectedTeam.payload);
    setRemoteReady(true);
    setSyncStatus("live");
    setSyncError("");
    await loadTeamMembers(client, selectedTeam.id);

    const nextParams = new URLSearchParams(window.location.search);
    nextParams.set("grupo", selectedTeam.id);
    nextParams.set("invite", selectedTeam.inviteToken);
    window.history.replaceState(null, "", `${window.location.pathname}?${nextParams.toString()}`);
  }

  useEffect(() => {
    setProfileName(localStorage.getItem(profileNameKey) ?? "");
    const saved = localStorage.getItem(storageKey);
    if (!saved) {
      setLocalHydrated(true);
      return;
    }

    try {
      const parsed = JSON.parse(saved) as { players: Player[]; venues?: Venue[]; matches: Match[]; activeMatchId: string; siteSettings?: SiteSettings };
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
    if (!localHydrated || !supabase) return;

    const client = supabase;
    let cancelled = false;

    async function connectGroup() {
      setSyncStatus("connecting");
      setSyncError("");

      try {
        const userId = await ensureUser(client);

        const params = new URLSearchParams(window.location.search);
        const inviteToken = params.get("invite");
        let groupId = params.get("grupo");

        if (inviteToken) {
          const joinResult = await client.rpc("join_pachanga_team", {
            member_name: profileName.trim() || "Jugador",
            token: inviteToken,
          });
          if (joinResult.error || !joinResult.data) throw new Error(joinResult.error?.message ?? "No se pudo entrar al grupo");
          groupId = String(joinResult.data);
        }

        await loadTeams(client, groupId);

        if (cancelled) return;
        void userId;
      } catch (error) {
        setSyncStatus("error");
        setSyncError(error instanceof Error ? error.message : "No se pudo cargar el equipo");
        return;
      }
    }

    void connectGroup();

    return () => {
      cancelled = true;
    };
  }, [localHydrated]);

  useEffect(() => {
    if (!supabase || !remoteGroupId || !remoteReady) return;

    const client = supabase;
    const channel = client
      .channel(`pachanga-group-${remoteGroupId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "pachanga_groups", filter: `id=eq.${remoteGroupId}` },
        (payload) => {
          const nextPayload = normalizePayload(payload.new.payload as Partial<AppPayload>);
          applyPayload(nextPayload);
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [remoteGroupId, remoteReady]);

  useEffect(() => {
    localStorage.setItem(storageKey, JSON.stringify({ players, venues, matches, activeMatchId, siteSettings }));

    if (!supabase || !remoteGroupId || !remoteReady || applyingRemoteRef.current) return;
    const client = supabase;
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      void client
        .from("pachanga_groups")
        .update({ payload: currentPayload() })
        .eq("id", remoteGroupId);
    }, 450);
  }, [players, venues, matches, activeMatchId, siteSettings]);

  useEffect(() => {
    if (!selectedPlayerId) return;
    playerProfileRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [selectedPlayerId]);

  const activeMatch = matches.find((match) => match.id === activeMatchId) ?? matches[0];
  const activeKind = activeMatch.kind ?? "futbol7";
  const activeVenue = venues.find((venue) => venue.id === activeMatch.venueId);
  const reserveLimit = reserveCapacity(activeMatch);
  const orderedGoingEntries = orderedGoingPlayers(activeMatch);
  const playingEntries = orderedGoingEntries.slice(0, activeMatch.targetPlayers);
  const reserveEntries = orderedGoingEntries.slice(activeMatch.targetPlayers, activeMatch.targetPlayers + reserveLimit);
  const waitingEntries = orderedGoingEntries.slice(activeMatch.targetPlayers + reserveLimit);
  const confirmedIds = playingEntries.map(({ entry }) => entry.playerId);
  const reserveIds = reserveEntries.map(({ entry }) => entry.playerId);
  const waitingIds = waitingEntries.map(({ entry }) => entry.playerId);
  const payingIds = [...confirmedIds, ...reserveIds];
  const confirmedPlayers = players.filter((player) => confirmedIds.includes(player.id));
  const reservePlayers = reserveIds.map((playerId) => players.find((player) => player.id === playerId)).filter((player): player is Player => Boolean(player));
  const waitingPlayers = waitingIds.map((playerId) => players.find((player) => player.id === playerId)).filter((player): player is Player => Boolean(player));
  const closedMatches = matches.filter((match) => match.scoreA !== undefined);
  const doubtfulCount = activeMatch.players.filter((entry) => entry.status === "duda").length;
  const missing = Math.max(activeMatch.targetPlayers - confirmedPlayers.length, 0);
  const fieldCost = activeMatch.fieldCost ?? 0;
  const sharePerPlayer = payingIds.length > 0 ? fieldCost / payingIds.length : 0;
  const paidCount = activeMatch.players.filter((entry) => payingIds.includes(entry.playerId) && entry.paid).length;
  const suggestedPayerId = nextPayer(players, matches, activeMatch, payingIds);
  const payerId = activeMatch.payerId && payingIds.includes(activeMatch.payerId) ? activeMatch.payerId : suggestedPayerId;
  const payer = players.find((player) => player.id === payerId);
  const balancedLineup = useMemo(() => balanceTeams(confirmedPlayers), [confirmedPlayers]);
  const suggested = savedTeams(activeMatch, players, confirmedIds) ?? balancedLineup;
  const lineupClosed = activeMatch.lineupClosed ?? false;
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

  function updateMatch(next: Match) {
    setMatches((current) => current.map((match) => (match.id === next.id ? next : match)));
  }

  function openPlayerProfile(playerId: string) {
    setSelectedPlayerId(playerId);
  }

  function setStatus(playerId: string, status: MatchPlayer["status"]) {
    const existing = activeMatch.players.find((entry) => entry.playerId === playerId);
    const joinedAt = status === "voy" ? (existing?.status === "voy" ? existing.joinedAt : new Date().toISOString()) : undefined;
    const nextPlayers = existing
      ? activeMatch.players.map((entry) => (entry.playerId === playerId ? { ...entry, status, joinedAt, paid: status === "voy" ? entry.paid : false } : entry))
      : [...activeMatch.players, { playerId, status, joinedAt, paid: false }];
    updateMatch({ ...activeMatch, players: nextPlayers });
  }

  function togglePaid(playerId: string) {
    updateMatch({
      ...activeMatch,
      players: activeMatch.players.map((entry) => (entry.playerId === playerId ? { ...entry, paid: !entry.paid } : entry)),
    });
  }

  function addPlayer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (remoteReady && !canManageTeam) return;
    const name = displayName(newPlayer);
    if (!name) return;

    const player: Player = {
      id: id(),
      name,
      phone: "",
      goalkeeperOnly: false,
      rating: 5,
      ratings: [],
      position: "Medio",
      goals: 0,
      assists: 0,
      appearances: 0,
      wins: 0,
      lateCancels: 0,
    };

    setPlayers((current) => [...current, player]);
    setNewPlayer("");
    setOpenQuickForm(null);
  }

  function createMatch() {
    if (remoteReady && !canManageTeam) return;
    const defaultVenue = venues.find((venue) => venue.id === activeMatch.venueId) ?? venues[0];
    const nextKind = activeMatch.kind ?? defaultVenue?.kind ?? "futbol7";
    const next: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextMatchDate(activeMatch.date),
      place: defaultVenue?.name ?? "Campo por confirmar",
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
    setActiveMatchId(next.id);
  }

  function toggleLineupClosed() {
    if (remoteReady && !canManageTeam) return;
    updateMatch({
      ...activeMatch,
      lineupClosed: !lineupClosed,
      teamA: suggested.teamA.map((player) => player.id),
      teamB: suggested.teamB.map((player) => player.id),
    });
  }

  function applyRandomTeams() {
    if (remoteReady && !canManageTeam) return;
    if (lineupClosed) return;
    const next = randomTeams(confirmedPlayers);
    updateMatch({
      ...activeMatch,
      teamA: next.teamA.map((player) => player.id),
      teamB: next.teamB.map((player) => player.id),
    });
  }

  function applyBalancedTeams() {
    if (remoteReady && !canManageTeam) return;
    if (lineupClosed) return;
    updateMatch({
      ...activeMatch,
      teamA: balancedLineup.teamA.map((player) => player.id),
      teamB: balancedLineup.teamB.map((player) => player.id),
    });
  }

  function assignPlayerTeam(playerId: string, team: "A" | "B") {
    if (remoteReady && !canManageTeam) return;
    if (lineupClosed) return;
    const baseTeamA = suggested.teamA.map((player) => player.id).filter((id) => id !== playerId);
    const baseTeamB = suggested.teamB.map((player) => player.id).filter((id) => id !== playerId);

    updateMatch({
      ...activeMatch,
      teamA: team === "A" ? [...baseTeamA, playerId] : baseTeamA,
      teamB: team === "B" ? [...baseTeamB, playerId] : baseTeamB,
    });
  }

  function setPlayerGoals(playerId: string, goals: number) {
    if (remoteReady && !canManageTeam) return;
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

    updateMatch({
      ...activeMatch,
      scorers: cleanScorers,
    });
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
            <span>{playerDisplayName(player)}</span>
            <button type="button" disabled={goals === 0} onClick={() => setPlayerGoals(player.id, goals - 1)}>-</button>
            <b>{goals}</b>
            <button type="button" disabled={!resultIsReady || assignedTeamGoals >= teamLimit} onClick={() => setPlayerGoals(player.id, goals + 1)}>+</button>
          </div>
        );
      })
      .filter(Boolean);
  }

  function finalizeMatch() {
    if (remoteReady && !canManageTeam) return;
    if (!resultIsReady) return;

    const scoreA = Number(scoreAValue);
    const scoreB = Number(scoreBValue);
    const winners = scoreA === scoreB ? [] : scoreA > scoreB ? suggested.teamA.map((player) => player.id) : suggested.teamB.map((player) => player.id);
    const previousGoalsByPlayer = new Map((activeMatch.scorers ?? []).map((entry) => [entry.playerId, entry.goals]));
    const shouldApplyMatchStats = !activeMatch.closed;

    setPlayers((current) =>
      current.map((player) =>
        confirmedIds.includes(player.id)
          ? {
              ...player,
              appearances: shouldApplyMatchStats ? player.appearances + 1 : player.appearances,
              goals: shouldApplyMatchStats ? player.goals + (previousGoalsByPlayer.get(player.id) ?? 0) : player.goals,
              wins: shouldApplyMatchStats && winners.includes(player.id) ? player.wins + 1 : player.wins,
            }
          : player,
      ),
    );

    updateMatch({
      ...activeMatch,
      scoreA,
      scoreB,
      closed: true,
      payerId,
      teamA: suggested.teamA.map((player) => player.id),
      teamB: suggested.teamB.map((player) => player.id),
    });
  }

  function deleteClosedMatch(matchId: string) {
    if (remoteReady && !canManageTeam) return;
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
    const replacementMatch: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextMatchDate(match.date),
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
    if (remoteReady && !canManageTeam) return;
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
    const replacementMatch: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextMatchDate(match.date),
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

  const rankedPlayers = [...players].sort((a, b) => scorePlayer(b) - scorePlayer(a));
  const sortedPlayers = [...players].sort((a, b) => {
    const statusOrder: Record<MatchPlayer["status"] | "sin", number> = { voy: 0, duda: 1, no: 2, sin: 3 };
    const statusA = activeMatch.players.find((entry) => entry.playerId === a.id)?.status ?? "sin";
    const statusB = activeMatch.players.find((entry) => entry.playerId === b.id)?.status ?? "sin";
    return statusOrder[statusA] - statusOrder[statusB] || a.name.localeCompare(b.name, "es");
  });
  const teamAPlayerIds = new Set(suggested.teamA.map((player) => player.id));
  const teamBPlayerIds = new Set(suggested.teamB.map((player) => player.id));
  const reservePlayerIds = new Set(reserveIds);
  const waitingPlayerIds = new Set(waitingIds);
  const sortedTeamA = sortedLineupPlayers(suggested.teamA);
  const sortedTeamB = sortedLineupPlayers(suggested.teamB);
  const otherPlayers = sortedPlayers.filter((player) => !teamAPlayerIds.has(player.id) && !teamBPlayerIds.has(player.id) && !reservePlayerIds.has(player.id) && !waitingPlayerIds.has(player.id));
  const selectedPlayer = selectedPlayerId ? players.find((player) => player.id === selectedPlayerId) : undefined;
  const currentTeam = remoteTeams.find((team) => team.id === remoteGroupId);
  const canManageTeam = currentRole === "owner" || currentRole === "admin";
  const canUseAdminControls = !remoteReady || canManageTeam;
  const canEditLineup = canUseAdminControls && !lineupClosed;

  function updateMatchSettings(next: Match) {
    if (!canUseAdminControls) return;
    updateMatch(next);
  }

  function updatePlayer(playerId: string, next: Partial<Player>) {
    if (remoteReady && !canManageTeam) return;
    setPlayers((current) => current.map((player) => (player.id === playerId ? { ...player, ...next } : player)));
  }

  function addPeerRating(playerId: string) {
    if (remoteReady && !canManageTeam) return;
    const rating = Math.max(1, Math.min(10, Number(newRating) || 5));
    setPlayers((current) =>
      current.map((player) => (player.id === playerId ? { ...player, ratings: [...(player.ratings ?? []), rating] } : player)),
    );
  }

  function uploadAvatar(file: File | undefined) {
    if (remoteReady && !canManageTeam) return;
    if (!file || !selectedPlayer) return;

    const reader = new FileReader();
    reader.onload = () => updatePlayer(selectedPlayer.id, { avatar: String(reader.result) });
    reader.readAsDataURL(file);
  }

  function changeKind(kind: MatchKind) {
    if (remoteReady && !canManageTeam) return;
    updateMatch({ ...activeMatch, kind, targetPlayers: matchKinds[kind].targetPlayers });
  }

  function selectVenue(venueId: string) {
    if (remoteReady && !canManageTeam) return;
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
    if (remoteReady && !canManageTeam) return;
    const name = newVenue.name.trim();
    if (!name) return;
    const kind = newVenue.kind;

    const venue: Venue = {
      id: id(),
      name,
      defaultCost: Number(newVenue.cost) || 0,
      kind,
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
    setNewVenue({ name: "", cost: String(venue.defaultCost || 56), kind });
    setOpenQuickForm(null);
  }

  async function createTeam(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;

    const client = supabase;
    setSyncStatus("connecting");
    setSyncError("");

    try {
      const userId = await ensureUser(client);
      const teamName = newTeamName.trim() || "Mi equipo pachanguero";
      const insertResult = await client
        .from("pachanga_groups")
        .insert({ name: teamName, owner_id: userId, payload: currentPayload() })
        .select("id, invite_token, name, payload, team_code")
        .single();

      if (insertResult.error || !insertResult.data) throw new Error(insertResult.error?.message ?? "No se pudo crear el equipo");

      const memberResult = await client.from("pachanga_group_members").insert({
        display_name: profileName.trim() || "Admin",
        group_id: insertResult.data.id,
        role: "owner",
        user_id: userId,
      });

      if (memberResult.error) throw new Error(memberResult.error.message);

      await loadTeams(client, insertResult.data.id);
      setOpenQuickForm(null);
    } catch (error) {
      setSyncStatus("error");
      setSyncError(error instanceof Error ? error.message : "No se pudo crear el equipo");
    }
  }

  async function deleteCurrentTeam() {
    if (!supabase || !remoteGroupId || currentRole !== "owner") return;
    const teamName = currentTeam?.name ?? "este equipo";
    if (!window.confirm(`¿Eliminar ${teamName}?`)) return;
    if (!window.confirm("Confirmación final: se borrarán el equipo y sus miembros.")) return;

    const client = supabase;
    setSyncStatus("connecting");
    setSyncError("");

    try {
      const deleteResult = await client.from("pachanga_groups").delete().eq("id", remoteGroupId);
      if (deleteResult.error) throw new Error(deleteResult.error.message);

      const nextTeam = remoteTeams.find((team) => team.id !== remoteGroupId);
      await loadTeams(client, nextTeam?.id ?? null);

      const nextParams = new URLSearchParams(window.location.search);
      if (nextTeam) {
        nextParams.set("grupo", nextTeam.id);
        nextParams.set("invite", nextTeam.inviteToken);
      } else {
        nextParams.delete("grupo");
        nextParams.delete("invite");
      }
      window.history.replaceState(null, "", nextParams.toString() ? `${window.location.pathname}?${nextParams.toString()}` : window.location.pathname);
    } catch (error) {
      setSyncStatus("error");
      setSyncError(error instanceof Error ? error.message : "No se pudo eliminar el equipo");
    }
  }

  function selectTeam(teamId: string) {
    const selectedTeam = remoteTeams.find((team) => team.id === teamId);
    if (!selectedTeam) return;

    setRemoteGroupId(selectedTeam.id);
    setRemoteInviteToken(selectedTeam.inviteToken);
    setCurrentRole(selectedTeam.role);
    applyPayload(selectedTeam.payload);
    setRemoteReady(true);
    setSyncStatus("live");
    setSyncError("");

    const nextParams = new URLSearchParams(window.location.search);
    nextParams.set("grupo", selectedTeam.id);
    nextParams.set("invite", selectedTeam.inviteToken);
    window.history.replaceState(null, "", `${window.location.pathname}?${nextParams.toString()}`);

    if (supabase) {
      void loadTeamMembers(supabase, selectedTeam.id).catch((error) => {
        setSyncStatus("error");
        setSyncError(error instanceof Error ? error.message : "No se pudieron cargar miembros");
      });
    }
  }

  async function updateMemberRole(member: RemoteMember, role: MemberRole) {
    if (!supabase || !remoteGroupId || currentRole !== "owner" || member.role === "owner") return;

    const result = await supabase
      .from("pachanga_group_members")
      .update({ role })
      .eq("group_id", remoteGroupId)
      .eq("user_id", member.userId);

    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }

    await loadTeamMembers(supabase, remoteGroupId);
  }

  function matchUrl() {
    if (!localHydrated || typeof window === "undefined") return "";
    const params = new URLSearchParams();
    if (remoteGroupId) params.set("grupo", remoteGroupId);
    if (remoteInviteToken) params.set("invite", remoteInviteToken);
    params.set("partido", activeMatch.id);
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
  }

  function currentTeamInviteUrl() {
    if (!localHydrated || typeof window === "undefined" || !remoteGroupId || !remoteInviteToken) return "";
    const params = new URLSearchParams();
    params.set("grupo", remoteGroupId);
    params.set("invite", remoteInviteToken);
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
  }

  async function copyTeamInvite() {
    const inviteUrl = currentTeamInviteUrl();
    if (!inviteUrl || !navigator.clipboard) return;

    try {
      await navigator.clipboard.writeText(inviteUrl);
      setSyncStatus("live");
      setSyncError("");
    } catch {
      setSyncStatus("error");
      setSyncError("No se pudo copiar el enlace");
    }
  }

  function shareTeamInviteWhatsApp() {
    const inviteUrl = currentTeamInviteUrl();
    if (!inviteUrl) return;
    const teamName = currentTeam?.name ?? "mi equipo";
    window.open(`https://wa.me/?text=${encodeURIComponent(`Únete a ${teamName}\n${inviteUrl}`)}`, "_blank", "noopener,noreferrer");
  }

  function shareText() {
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
      matchUrl(),
    ]
      .filter(Boolean)
      .join("\n");
  }

  function shareWhatsApp() {
    window.open(`https://wa.me/?text=${encodeURIComponent(shareText())}`, "_blank", "noopener,noreferrer");
  }

  async function copyMatchLink() {
    const url = matchUrl();
    if (!url || !navigator.clipboard) return;

    try {
      await navigator.clipboard.writeText(url);
      setSyncStatus("live");
      setSyncError("");
    } catch {
      setSyncStatus("error");
      setSyncError("No se pudo copiar el partido");
    }
  }

  function renderPlayerCard(player: Player, team?: "A" | "B") {
    const matchEntry = activeMatch.players.find((entry) => entry.playerId === player.id);
    const status = matchEntry?.status;
    const isReserve = reserveIds.includes(player.id);
    const isWaiting = waitingIds.includes(player.id);
    const teamClass = team === "A" ? "team-a-card" : team === "B" ? "team-b-card" : "";
    const nextTeam = team === "A" ? "B" : "A";

    return (
      <article className={`player-card ${status ? `status-${status}` : "status-sin"} ${teamClass} ${isReserve ? "reserve-card" : ""} ${isWaiting ? "waiting-card" : ""} ${playerPosition(player) === "Porteria" ? "goalkeeper-card" : ""}`} key={player.id}>
        <div>
          <button className="player-name" onClick={() => openPlayerProfile(player.id)}>
            {player.avatar ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={player.avatar} alt="" />
            ) : null}
            <strong>
              {playerDisplayName(player)} <small>({scorePlayer(player).toFixed(1)}) {player.goals} Goles</small>
            </strong>
          </button>
          <span className="player-meta">
            {positionLabel(player)}
            {isReserve ? <em className="reserve-chip">Reserva</em> : null}
            {isWaiting ? <em className="reserve-chip">Espera</em> : null}
          </span>
        </div>
        {payerId === player.id ? (
          <span className="payer-badge" title="Le toca pagar el campo" aria-label="Le toca pagar el campo">
            $
          </span>
        ) : null}
        <div className="player-actions">
          <div className="status-buttons" aria-label={`Estado de ${playerDisplayName(player)}`}>
            <button className={status === "voy" ? "selected" : ""} onClick={() => setStatus(player.id, "voy")}>Voy</button>
            <button className={status === "duda" ? "selected" : ""} onClick={() => setStatus(player.id, "duda")}>Duda</button>
            <button className={status === "no" ? "selected danger" : ""} onClick={() => setStatus(player.id, "no")}>No</button>
          </div>
          {status === "voy" && team && canUseAdminControls ? (
            <button
              className={`team-move ${team === "A" ? "to-b" : "to-a"}`}
              disabled={lineupClosed}
              onClick={() => assignPlayerTeam(player.id, nextTeam)}
              title={team === "A" ? "Mover al equipo 2" : "Mover al equipo 1"}
              type="button"
            >
              {team === "A" ? "→" : "←"}
            </button>
          ) : null}
          {status === "voy" && !isWaiting ? (
            <button
              className={matchEntry?.paid ? "paid-button paid" : "paid-button"}
              onClick={() => togglePaid(player.id)}
              title={matchEntry?.paid ? "Pago recibido" : "Marcar pago recibido"}
              aria-label={matchEntry?.paid ? "Pago recibido" : "Marcar pago recibido"}
            >
              $
            </button>
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

  return (
    <main className="min-h-screen bg-[#f7f6f0] text-[#1d2521]" style={teamColorStyle}>
      <section className="hero">
        <div>
          <p className="eyebrow">{siteSettings.brand}</p>
          <h1>{siteSettings.title}</h1>
          <p className="hero-copy">{siteSettings.subtitle}</p>
        </div>
        <div className="hero-actions">
          <button className="primary-button" onClick={createMatch} disabled={remoteReady && !canManageTeam}>
            + Partido
          </button>
          <button className="secondary-button" onClick={() => setOpenQuickForm(openQuickForm === "player" ? null : "player")} disabled={remoteReady && !canManageTeam}>
            + Jugador
          </button>
          <button className="secondary-button" onClick={() => setOpenQuickForm(openQuickForm === "venue" ? null : "venue")} disabled={remoteReady && !canManageTeam}>
            + Campo
          </button>
          <button className="secondary-button" onClick={() => setOpenQuickForm(openQuickForm === "team" ? null : "team")}>
            + Equipo
          </button>
          <button className="secondary-button" onClick={() => setShowSettings((current) => !current)} disabled={remoteReady && !canManageTeam}>
            Configurar
          </button>
        </div>
      </section>

      {openQuickForm === "team" ? (
        <form className="top-panel team-create-form top-team-form" onSubmit={createTeam}>
          <input value={newTeamName} onChange={(event) => setNewTeamName(event.target.value)} placeholder="Nombre del nuevo equipo" />
          <button type="submit">Crear equipo</button>
          <button className="ghost-form-button" type="button" onClick={() => setOpenQuickForm(null)}>Cerrar</button>
        </form>
      ) : null}

      <section className="top-panel team-access-panel">
        <div className="team-access-current">
          <span>Equipo pachanguero</span>
          {remoteTeams.length > 0 ? (
            <select value={remoteGroupId ?? ""} onChange={(event) => selectTeam(event.target.value)}>
              {remoteTeams.map((team) => (
                <option key={team.id} value={team.id}>{team.name}</option>
              ))}
            </select>
          ) : (
            <strong>Sin equipo todavía</strong>
          )}
        </div>
        <div className="team-access-meta">
          <span>ID equipo</span>
          <strong>{currentTeam?.teamCode ?? "-"}</strong>
        </div>
        <div className="team-access-meta">
          <span>Rol</span>
          <strong>{currentRole === "owner" || currentRole === "admin" ? "Admin" : currentRole === "player" ? "Jugador" : "-"}</strong>
        </div>
        <div className="team-invite-link">
          <span>Invitar a equipo</span>
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
          disabled={!remoteGroupId || currentRole !== "owner"}
          onClick={() => void deleteCurrentTeam()}
          title="Eliminar equipo"
          type="button"
          aria-label="Eliminar equipo"
        >
          <TrashLogo />
        </button>
        <small className={`sync-status sync-${syncStatus}`}>
          {syncStatus === "live" ? "Equipo privado sincronizado" : syncStatus === "connecting" ? "Conectando..." : syncStatus === "error" ? `Sin sync: ${syncError}` : "Crea un equipo o entra con invitación"}
        </small>
      </section>

      {showSettings ? (
        <section className="top-panel settings-panel">
          <label>
            Nombre
            <input value={siteSettings.brand} onChange={(event) => setSiteSettings({ ...siteSettings, brand: event.target.value })} />
          </label>
          <label>
            Título
            <input value={siteSettings.title} onChange={(event) => setSiteSettings({ ...siteSettings, title: event.target.value })} />
          </label>
          <label>
            Subtítulo
            <input value={siteSettings.subtitle} onChange={(event) => setSiteSettings({ ...siteSettings, subtitle: event.target.value })} />
          </label>
          <div className="palette-field">
            <span>Color equipo 1</span>
            <div className="color-select">
              <span style={{ background: siteSettings.teamAColor }} />
              <select value={siteSettings.teamAColor} onChange={(event) => setSiteSettings({ ...siteSettings, teamAColor: event.target.value })}>
                {teamPalette.map((color) => (
                  <option key={`team-a-${color.value}`} value={color.value}>{color.name}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="palette-field">
            <span>Color equipo 2</span>
            <div className="color-select">
              <span style={{ background: siteSettings.teamBColor }} />
              <select value={siteSettings.teamBColor} onChange={(event) => setSiteSettings({ ...siteSettings, teamBColor: event.target.value })}>
                {teamPalette.map((color) => (
                  <option key={`team-b-${color.value}`} value={color.value}>{color.name}</option>
                ))}
              </select>
            </div>
          </div>
          <button className="panel-hide-button" type="button" onClick={() => setShowSettings(false)}>
            Guardar
          </button>
        </section>
      ) : null}

      {openQuickForm === "player" ? (
        <form className="top-panel add-player top-player-form" onSubmit={addPlayer}>
          <input placeholder="Nombre del jugador" value={newPlayer} onChange={(event) => setNewPlayer(event.target.value)} />
          <button type="submit">Guardar jugador</button>
        </form>
      ) : null}

      {openQuickForm === "venue" ? (
        <form className="top-panel venue-form top-venue-form" onSubmit={addVenue}>
          <input
            placeholder="Crear campo: nombre"
            value={newVenue.name}
            onChange={(event) => setNewVenue({ ...newVenue, name: event.target.value })}
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
          <button type="submit">Guardar campo</button>
        </form>
      ) : null}

      <section className="app-shell">
        <aside className="panel match-list" aria-label="Partidos">
          {teamMembers.length > 0 ? (
            <details className="team-members">
              <summary>
                <span>Miembros</span>
                <strong>{teamMembers.length}</strong>
              </summary>
              <div>
                {teamMembers.map((member) => (
                  <label key={member.userId}>
                    <strong>
                      {member.displayName}
                      {member.userId === currentUserId ? " (tú)" : ""}
                    </strong>
                    <select
                      value={member.role}
                      disabled={currentRole !== "owner" || member.role === "owner"}
                      onChange={(event) => void updateMemberRole(member, event.target.value as MemberRole)}
                    >
                      <option value="owner">Admin</option>
                      <option value="admin">Admin</option>
                      <option value="player">Jugador</option>
                    </select>
                  </label>
                ))}
              </div>
            </details>
          ) : null}
          <div className="panel-title">
            <span>Próximos partidos</span>
            <strong>{matches.length}</strong>
          </div>
          {matches.map((match) => (
            <div className="match-row" key={match.id}>
              <button
                className={match.id === activeMatch.id ? "match-item active" : "match-item"}
                onClick={() => setActiveMatchId(match.id)}
              >
                <span>{match.title}</span>
                <small>{new Date(match.date).toLocaleString("es-ES", { weekday: "short", hour: "2-digit", minute: "2-digit" })}</small>
              </button>
              <button
                className="trash-icon-button"
                disabled={!canUseAdminControls}
                onClick={() => deleteMatch(match.id)}
                title="Borrar partido"
                type="button"
                aria-label={`Borrar ${match.title}`}
              >
                <TrashLogo />
              </button>
            </div>
          ))}
          <div className="side-history">
            <div className="panel-title compact-title">
              <span>Historial</span>
              <strong>{closedMatches.length}</strong>
            </div>
            <div className="history">
              {closedMatches.map((match) => {
                const matchPayer = players.find((player) => player.id === match.payerId);
                const scorersText = match.scorers
                  ?.map((entry) => {
                    const scorer = players.find((player) => player.id === entry.playerId);
                    return `${scorer ? playerDisplayName(scorer) : "Jugador"} ${entry.goals}`;
                  })
                  .join(", ");

                return (
                  <article className="history-item" key={match.id}>
                    <div>
                      <strong>{match.title}</strong>
                      <small>{new Date(match.date).toLocaleDateString("es-ES", { day: "2-digit", month: "short" })}</small>
                    </div>
                    <span>{match.scoreA} - {match.scoreB}</span>
                    <button
                      className="history-delete"
                      type="button"
                      onClick={() => {
                        if (window.confirm("¿Borrar este partido y descontar sus estadísticas?")) deleteClosedMatch(match.id);
                      }}
                    >
                      Borrar
                    </button>
                    <small>
                      {match.place} · pagó {matchPayer ? playerDisplayName(matchPayer) : "sin asignar"}
                      {scorersText ? ` · goles: ${scorersText}` : ""}
                    </small>
                  </article>
                );
              })}
            </div>
          </div>
        </aside>

        <section className="panel main-panel">
          <div className={canUseAdminControls ? "match-editor" : "match-editor readonly-editor"}>
            {!canUseAdminControls ? <span className="admin-only-badge">Solo admin</span> : null}
            <label>
              Campo
              <select value={activeMatch.venueId ?? ""} onChange={(event) => selectVenue(event.target.value)} disabled={!canUseAdminControls}>
                <option value="" disabled>Selecciona campo</option>
                {venues.map((venue) => (
                  <option key={venue.id} value={venue.id}>{venue.name}</option>
                ))}
              </select>
            </label>
            <label>
              Fecha
              <input
                type="datetime-local"
                step="600"
                value={activeMatch.date}
                disabled={!canUseAdminControls}
                onChange={(event) => updateMatchSettings({ ...activeMatch, date: event.target.value })}
              />
            </label>
            <label>
              Modalidad
              <select value={activeKind} onChange={(event) => changeKind(event.target.value as MatchKind)} disabled={!canUseAdminControls}>
                {Object.entries(matchKinds).map(([kind, config]) => (
                  <option key={kind} value={kind}>{config.label}</option>
                ))}
              </select>
            </label>
            <label>
              Precio
              <input
                type="number"
                min="0"
                value={fieldCost}
                disabled={!canUseAdminControls}
                onChange={(event) => updateMatchSettings({ ...activeMatch, fieldCost: Number(event.target.value) })}
              />
            </label>
            <label className="reserve-toggle">
              Reservas
              <span className="reserve-toggle-box">
                <input
                  type="checkbox"
                  checked={Boolean(activeMatch.reservesAttend)}
                  disabled={!canUseAdminControls}
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
                value={activeMatch.reserveLimit ?? 0}
                disabled={!canUseAdminControls || !activeMatch.reservesAttend}
                onChange={(event) => updateMatchSettings({ ...activeMatch, reserveLimit: Math.max(0, Math.floor(Number(event.target.value) || 0)) })}
              />
            </label>
          </div>

          <div className="stats-row">
            <div>
              <span>Confirmados</span>
              <strong>{confirmedPlayers.length}/{activeMatch.targetPlayers}</strong>
            </div>
            <div>
              <span>Faltan</span>
              <strong>{missing}</strong>
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
              <span>Toca</span>
              <strong>{sharePerPlayer.toFixed(2)} €</strong>
            </div>
            <div>
              <span>Campo</span>
              <strong>{fieldCost.toFixed(0)} €</strong>
            </div>
            <div>
              <span>Paga</span>
              <strong>{payer?.name ?? "-"}</strong>
            </div>
            <div>
              <span>Pagados</span>
              <strong>{paidCount}/{payingIds.length}</strong>
            </div>
          </div>

          <div className="payer-note">
            <span>Turno de pago</span>
            <strong>
              {payer
                ? `${playerDisplayName(payer)} adelanta el campo. Bizum: ${payer.phone || "sin telefono"} · ${sharePerPlayer.toFixed(2)} € por persona`
                : "Añade asistentes para calcularlo"}
            </strong>
          </div>

          <div className="share-box">
            <span>Comparte este partido!</span>
            <div className="share-actions">
              <button className="copy-invite-button" type="button" onClick={() => void copyMatchLink()} disabled={!matchUrl()} title="Copiar link del partido" aria-label="Copiar link del partido">
                Copiar link
              </button>
              <button className="whatsapp-icon-button" type="button" onClick={shareWhatsApp} disabled={!matchUrl()} title="Enviar partido por WhatsApp" aria-label="Enviar partido por WhatsApp">
                <WhatsAppLogo />
              </button>
            </div>
            <small className={`sync-status sync-${syncStatus}`}>
              {syncStatus === "live" ? "Sincronizado" : syncStatus === "connecting" ? "Conectando..." : syncStatus === "error" ? `Sin sync: ${syncError}` : "Modo local"}
            </small>
          </div>

          <div className="team-player-grid">
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
          </div>

          {reservePlayers.length > 0 ? (
            <div className="reserve-section">
              <div className="team-column-title">
                <span>Reservas que van</span>
                <strong>{reservePlayers.length}</strong>
              </div>
              <div className="player-grid reserve-player-grid">
                {reservePlayers.map((player) => renderPlayerCard(player))}
              </div>
            </div>
          ) : null}

          {waitingPlayers.length > 0 ? (
            <div className="reserve-section waiting-section">
              <div className="team-column-title">
                <span>Lista de espera</span>
                <strong>{waitingPlayers.length}</strong>
              </div>
              <div className="player-grid reserve-player-grid">
                {waitingPlayers.map((player) => renderPlayerCard(player))}
              </div>
            </div>
          ) : null}

          {otherPlayers.length > 0 ? (
            <div className="player-grid other-player-grid">
              {otherPlayers.map((player) => renderPlayerCard(player))}
            </div>
          ) : null}
        </section>

        <aside className="panel teams-panel">
          <div className="panel-title">
            <span>Equipos sugeridos</span>
            <strong>{matchKinds[activeKind].teamSize}v{matchKinds[activeKind].teamSize}</strong>
          </div>
          <MatchPitch teamA={suggested.teamA} teamB={suggested.teamB} kind={activeKind} />
          <div className={lineupClosed ? "lineup-state closed" : "lineup-state"}>
            {lineupClosed ? "Alineación cerrada" : "Alineación abierta"}
          </div>
          <div className="lineup-actions">
            <button type="button" onClick={applyRandomTeams} disabled={!canEditLineup}>Aleatorio</button>
            <button type="button" onClick={applyBalancedTeams} disabled={!canEditLineup}>Equilibrado por stats</button>
          </div>
          <Team title="Equipo 1" players={suggested.teamA} variant="team-a" />
          <Team title="Equipo 2" players={suggested.teamB} variant="team-b" />
          {canUseAdminControls ? (
            <button className="primary-button full" onClick={toggleLineupClosed}>
              {lineupClosed ? "Abrir alineación" : "Cerrar alineación"}
            </button>
          ) : null}
          <div className="result-box">
            <span>Resultado</span>
            <div>
              <input type="number" min="0" value={result.a} onChange={(event) => setResult({ ...result, a: event.target.value })} inputMode="numeric" />
              <b>-</b>
              <input type="number" min="0" value={result.b} onChange={(event) => setResult({ ...result, b: event.target.value })} inputMode="numeric" />
            </div>
            <div className="scorers-box">
              <strong>Goles</strong>
              {confirmedPlayers.length === 0 ? <small>Marca asistentes para añadir goleadores.</small> : null}
              {confirmedPlayers.length > 0 && !resultIsReady ? <small>Rellena primero el resultado.</small> : null}
              {confirmedPlayers.length > 0 && resultIsReady ? (
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
            <button disabled={!resultIsReady || !canUseAdminControls} onClick={finalizeMatch}>Finalizar partido</button>
          </div>
        </aside>
      </section>

      <section className={selectedPlayer ? "bottom-grid" : "bottom-grid without-profile"}>
        {selectedPlayer ? (
          <div className="panel player-profile" ref={playerProfileRef}>
            <div className="panel-title">
              <span>Ficha jugador</span>
              <strong>{scorePlayer(selectedPlayer).toFixed(1)}</strong>
            </div>
            <>
              <div className="profile-top">
                <label className="avatar-picker">
                  {selectedPlayer.avatar ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={selectedPlayer.avatar} alt={`Foto de ${playerDisplayName(selectedPlayer)}`} />
                  ) : (
                    <span className="avatar-empty">+</span>
                  )}
                  <input type="file" accept="image/*" onChange={(event) => uploadAvatar(event.target.files?.[0])} />
                </label>
                <div>
                  <select value={selectedPlayer.id} onChange={(event) => setSelectedPlayerId(event.target.value)}>
                    {players.map((player) => (
                      <option key={player.id} value={player.id}>{playerDisplayName(player)}</option>
                    ))}
                  </select>
                  <input
                    value={selectedPlayer.name}
                    onBlur={() => updatePlayer(selectedPlayer.id, { name: displayName(selectedPlayer.name) })}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { name: event.target.value })}
                  />
                  <input
                    inputMode="tel"
                    placeholder="Teléfono Bizum"
                    value={selectedPlayer.phone ?? ""}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { phone: event.target.value })}
                  />
                </div>
              </div>
              <div className="profile-fields">
                <label className="toggle-field">
                  <input
                    type="checkbox"
                    checked={Boolean(selectedPlayer.goalkeeperOnly)}
                    onChange={(event) =>
                      updatePlayer(selectedPlayer.id, {
                        goalkeeperOnly: event.target.checked,
                        position: event.target.checked ? "Porteria" : selectedPlayer.position,
                      })
                    }
                  />
                  Portero fijo
                </label>
                <label>
                  Posición preferida
                  <select
                    value={selectedPlayer.position}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { position: event.target.value as Player["position"] })}
                  >
                    <option>Porteria</option>
                    <option>Defensa</option>
                    <option>Medio</option>
                    <option>Ataque</option>
                  </select>
                </label>
                <label>
                  Valor base
                  <input
                    type="number"
                    min="1"
                    max="10"
                    value={selectedPlayer.rating}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { rating: Number(event.target.value) })}
                  />
                </label>
                <div className="rating-box">
                  <span>Valoraciones</span>
                  <strong>{peerAverage(selectedPlayer).toFixed(1)}</strong>
                  <small>{selectedPlayer.ratings?.length ?? 0} votos de compañeros</small>
                  <div>
                    <input
                      type="number"
                      min="1"
                      max="10"
                      value={newRating}
                      onChange={(event) => setNewRating(event.target.value)}
                    />
                    <button type="button" onClick={() => addPeerRating(selectedPlayer.id)}>Añadir valoración</button>
                  </div>
                </div>
                <label>
                  Goles
                  <input
                    type="number"
                    min="0"
                    value={selectedPlayer.goals}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { goals: Number(event.target.value) })}
                  />
                </label>
              </div>
            </>
          </div>
        ) : null}

        <div className="panel">
          <div className="panel-title">
            <span>Ranking vivo</span>
            <strong>{rankedPlayers.length}</strong>
          </div>
          <div className="ranking">
            {rankedPlayers.slice(0, 8).map((player, index) => (
              <div key={player.id}>
                <span>{index + 1}</span>
                <strong>{playerDisplayName(player)}</strong>
                <small>{scorePlayer(player).toFixed(1)} pts · {player.goals} goles · {player.wins} victorias</small>
              </div>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}

function Team({ title, players, variant }: { title: string; players: Player[]; variant: "team-a" | "team-b" }) {
  const orderedPlayers = sortedLineupPlayers(players);

  return (
    <div className={`team ${variant}`}>
      <h2>{title}</h2>
      {players.length === 0 ? <p>Marca jugadores como “Voy”.</p> : null}
      {orderedPlayers.map((player) => (
        <div className={playerPosition(player) === "Porteria" ? "goalkeeper-row" : ""} key={player.id}>
          <span>
            {playerDisplayName(player)}
            <em>({scorePlayer(player).toFixed(1)}) {player.goals} Goles</em>
          </span>
          <small className="position-pill">{positionLabel(player)}</small>
        </div>
      ))}
    </div>
  );
}

function MatchPitch({ teamA, teamB, kind }: { teamA: Player[]; teamB: Player[]; kind: MatchKind }) {
  const teamATokens = placeTeam(teamA, kind, "bottom");
  const teamBTokens = placeTeam(teamB, kind, "top");
  const emptySlots = [
    ...teamATokens.empty.map((slot) => ({ ...slot, variant: "team-a" as const })),
    ...teamBTokens.empty.map((slot) => ({ ...slot, variant: "team-b" as const })),
  ];
  const tokens = [
    ...teamATokens.players.map((token) => ({ ...token, variant: "team-a" as const })),
    ...teamBTokens.players.map((token) => ({ ...token, variant: "team-b" as const })),
  ];

  return (
    <div className="match-pitch" aria-label="Campo completo con alineaciones">
      <div className="pitch-label top">Equipo 2</div>
      <div className="pitch-label bottom">Equipo 1</div>
      <div className="midline" />
      <div className="center-circle" />
      <div className="goal-box top" />
      <div className="goal-box bottom" />
      {tokens.length === 0 ? <p>Marca jugadores como “Voy”.</p> : null}
      {emptySlots.map((slot, index) => (
        <div
          className={`empty-token ${slot.variant}`}
          key={`${slot.variant}-empty-${index}`}
          style={{ left: `${slot.x}%`, top: `${slot.y}%` }}
          title="Falta jugador"
        >
          <b>Falta</b>
        </div>
      ))}
      {tokens.map(({ player, x, y, variant }) => (
        <button
          className={`player-token ${variant}`}
          key={player.id}
          style={{ left: `${x}%`, top: `${y}%` }}
          title={`${playerDisplayName(player)} · ${playerPosition(player)} · ${scorePlayer(player).toFixed(1)}`}
        >
          {player.avatar ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={player.avatar} alt="" />
          ) : (
            <span>{playerDisplayName(player).slice(0, 2).toUpperCase()}</span>
          )}
          <b>{playerDisplayName(player).split(" ")[0]}</b>
        </button>
      ))}
    </div>
  );
}

function placeTeam(players: Player[], kind: MatchKind, side: "top" | "bottom") {
  const sorted = [...players].sort((a, b) => {
    const order: Record<Player["position"], number> = { Porteria: 0, Defensa: 1, Medio: 2, Ataque: 3 };
    return order[playerPosition(a)] - order[playerPosition(b)] || scorePlayer(b) - scorePlayer(a);
  });
  const slots = formationSlots(kind, side);

  const placedPlayers = sorted.map((player, index) => {
    const preferred = slots.find((slot) => slot.position === playerPosition(player) && !slot.used);
    const fallback = slots.find((slot) => !slot.used) ?? slots[slots.length - 1];
    const slot = preferred ?? fallback;
    slot.used = true;

    if (index >= slots.length) {
      const extraOffset = index - slots.length + 1;
      return {
        player,
        x: 18 + ((extraOffset * 17) % 64),
        y: side === "top" ? 44 : 56,
      };
    }

    return { player, x: slot.x, y: slot.y };
  });

  return {
    players: placedPlayers,
    empty: slots.filter((slot) => !slot.used).map((slot) => ({ x: slot.x, y: slot.y })),
  };
}

function formationSlots(kind: MatchKind, side: "top" | "bottom") {
  const rows: Record<MatchKind, Array<{ position: Player["position"]; count: number; y: number }>> = {
    sala: [
      { position: "Porteria", count: 1, y: 6 },
      { position: "Defensa", count: 2, y: 20 },
      { position: "Medio", count: 1, y: 32 },
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

  return rows[kind].flatMap((row) =>
    spreadX(row.count).map((x) => ({
      position: row.position,
      x,
      y: side === "top" ? row.y : 100 - row.y,
      used: false,
    })),
  );
}

function spreadX(count: number) {
  if (count === 1) return [50];
  if (count === 2) return [32, 68];
  const gap = Math.min(70 / (count - 1), 22);
  const start = 50 - (gap * (count - 1)) / 2;
  return Array.from({ length: count }, (_, index) => start + gap * index);
}
