"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../supabaseClient";

type GuestAccess = {
  groupId?: string;
  id: string;
  matchId?: string;
  revision: number;
  serverSequence: number;
  status: "accepted" | "revoked";
};

type GuestPlayer = {
  avatar?: string;
  avatarOffsetX?: number;
  avatarOffsetY?: number;
  id: string;
  injured?: boolean;
  name: string;
  position?: string;
  rating?: number;
  status?: string;
  team?: "A" | "B";
};

type GuestMatch = {
  confirmedCount: number;
  date?: string;
  finalized: boolean;
  id: string;
  kind?: string;
  lineupClosed: boolean;
  place?: unknown;
  reserveLimit?: number;
  scoreA?: number;
  scoreB?: number;
  targetPlayers: number;
  teamA: string[];
  teamB: string[];
  title: string;
};

type GuestSnapshot = {
  groupName: string;
  match: GuestMatch;
  players: GuestPlayer[];
};

type GuestMatchState = {
  access: GuestAccess;
  serverSequence?: number;
  snapshot?: GuestSnapshot;
  snapshotId?: string;
  snapshotRevision?: number;
  sourcePayloadRevision?: number;
  updatedAt?: string;
};

function guestOperationMetadata() {
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-guest-match" : "web-guest-match",
  };
}

function normalizeGuestState(value: unknown): GuestMatchState | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  const accessRow = row.access as Record<string, unknown> | undefined;
  if (!accessRow || typeof accessRow.id !== "string") return null;
  const status = accessRow.status === "accepted" ? "accepted" : "revoked";
  const snapshotRow = row.snapshot && typeof row.snapshot === "object" ? row.snapshot as Record<string, unknown> : null;
  const matchRow = snapshotRow?.match && typeof snapshotRow.match === "object" ? snapshotRow.match as Record<string, unknown> : null;
  const players = Array.isArray(snapshotRow?.players) ? snapshotRow.players.flatMap((player) => {
    if (!player || typeof player !== "object") return [];
    const item = player as Record<string, unknown>;
    if (typeof item.id !== "string") return [];
    return [{
      avatar: typeof item.avatar === "string" ? item.avatar : undefined,
      avatarOffsetX: Number.isFinite(Number(item.avatarOffsetX)) ? Number(item.avatarOffsetX) : undefined,
      avatarOffsetY: Number.isFinite(Number(item.avatarOffsetY)) ? Number(item.avatarOffsetY) : undefined,
      id: item.id,
      injured: Boolean(item.injured),
      name: typeof item.name === "string" ? item.name : "Jugador",
      position: typeof item.position === "string" ? item.position : undefined,
      rating: Number.isFinite(Number(item.rating)) ? Number(item.rating) : undefined,
      status: typeof item.status === "string" ? item.status : undefined,
      team: item.team === "A" || item.team === "B" ? item.team : undefined,
    } satisfies GuestPlayer];
  }) : [];
  const snapshot = snapshotRow && matchRow && typeof matchRow.id === "string" ? {
    groupName: typeof snapshotRow.groupName === "string" ? snapshotRow.groupName : "Grupo de pachangas",
    match: {
      confirmedCount: Math.max(0, Math.floor(Number(matchRow.confirmedCount) || 0)),
      date: typeof matchRow.date === "string" ? matchRow.date : undefined,
      finalized: Boolean(matchRow.finalized),
      id: matchRow.id,
      kind: typeof matchRow.kind === "string" ? matchRow.kind : undefined,
      lineupClosed: Boolean(matchRow.lineupClosed),
      place: matchRow.place,
      reserveLimit: Number.isFinite(Number(matchRow.reserveLimit)) ? Number(matchRow.reserveLimit) : undefined,
      scoreA: Number.isFinite(Number(matchRow.scoreA)) ? Number(matchRow.scoreA) : undefined,
      scoreB: Number.isFinite(Number(matchRow.scoreB)) ? Number(matchRow.scoreB) : undefined,
      targetPlayers: Math.max(0, Math.floor(Number(matchRow.targetPlayers) || 0)),
      teamA: Array.isArray(matchRow.teamA) ? matchRow.teamA.filter((id): id is string => typeof id === "string") : [],
      teamB: Array.isArray(matchRow.teamB) ? matchRow.teamB.filter((id): id is string => typeof id === "string") : [],
      title: typeof matchRow.title === "string" ? matchRow.title : "Partido",
    },
    players,
  } satisfies GuestSnapshot : undefined;
  return {
    access: {
      groupId: typeof accessRow.groupId === "string" ? accessRow.groupId : undefined,
      id: accessRow.id,
      matchId: typeof accessRow.matchId === "string" ? accessRow.matchId : undefined,
      revision: Math.max(1, Math.floor(Number(accessRow.revision) || 1)),
      serverSequence: Math.max(0, Math.floor(Number(accessRow.serverSequence) || 0)),
      status,
    },
    serverSequence: Math.max(0, Math.floor(Number(row.serverSequence) || 0)),
    snapshot,
    snapshotId: typeof row.snapshotId === "string" ? row.snapshotId : undefined,
    snapshotRevision: row.snapshotRevision === undefined ? undefined : Math.max(1, Math.floor(Number(row.snapshotRevision) || 1)),
    sourcePayloadRevision: row.sourcePayloadRevision === undefined ? undefined : Math.max(0, Math.floor(Number(row.sourcePayloadRevision) || 0)),
    updatedAt: typeof row.updatedAt === "string" ? row.updatedAt : undefined,
  };
}

function displayDate(value?: string) {
  if (!value) return "Fecha por confirmar";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "full",
    timeStyle: "short",
  }).format(parsed);
}

function displayPlace(value: unknown) {
  if (typeof value === "string") return value;
  if (!value || typeof value !== "object") return "Campo por confirmar";
  const place = value as Record<string, unknown>;
  return [place.name, place.address, place.city].find((item): item is string => typeof item === "string" && item.trim().length > 0)
    ?? "Campo por confirmar";
}

function PlayerRow({ player }: { player: GuestPlayer }) {
  return (
    <li>
      <span className="guest-player-avatar">
        {player.avatar ? (
          // External player avatars are user-provided and intentionally bypass Next image optimization.
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={player.avatar}
            alt=""
            draggable={false}
            style={{ objectPosition: `${player.avatarOffsetX ?? 50}% ${player.avatarOffsetY ?? 0}%` }}
          />
        ) : player.name.slice(0, 2).toUpperCase()}
      </span>
      <span>
        <strong>{player.name}</strong>
        <small>{[player.position, player.injured ? "Lesionado" : null].filter(Boolean).join(" · ") || "Jugador"}</small>
      </span>
      {player.rating !== undefined ? <b>{Math.round(player.rating * (player.rating <= 10 ? 10 : 1))}</b> : null}
    </li>
  );
}

function GuestMatchContent() {
  const accessId = useSearchParams().get("acceso") ?? "";
  const [state, setState] = useState<GuestMatchState | null>(null);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [confirmLeave, setConfirmLeave] = useState(false);
  const [leaving, setLeaving] = useState(false);

  const loadGuestMatch = useCallback(async (targetAccessId: string) => {
    if (!supabase || !targetAccessId) return;
    const result = await supabase.rpc("get_pachanga_guest_match_snapshot_v1", { target_access_id: targetAccessId });
    if (result.error) {
      setMessage(result.error.message);
      setLoading(false);
      return null;
    } else {
      const nextState = normalizeGuestState(result.data);
      setState(nextState);
      setMessage("");
      setLoading(false);
      return nextState;
    }
  }, []);

  useEffect(() => {
    const client = supabase;
    if (!accessId || !client) return;

    let disposed = false;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(async ({ data }) => {
      if (!data.session?.user) {
        if (!disposed) {
          setMessage("Entra con tu cuenta para consultar la invitación.");
          setLoading(false);
        }
        return;
      }
      if (disposed) return;
      const initialState = await loadGuestMatch(accessId);
      if (disposed) return;
      channel = client.channel(`guest-match-${accessId}`)
        .on("postgres_changes", {
          event: "*",
          schema: "public",
          table: "pachanga_match_guest_access",
          filter: `id=eq.${accessId}`,
        }, () => void loadGuestMatch(accessId));
      if (initialState?.snapshotId) {
        channel = channel.on("postgres_changes", {
          event: "*",
          schema: "public",
          table: "pachanga_match_guest_snapshots",
          filter: `id=eq.${initialState.snapshotId}`,
        }, () => void loadGuestMatch(accessId));
      }
      channel.subscribe();
    });
    return () => {
      disposed = true;
      if (channel) void client.removeChannel(channel);
    };
  }, [accessId, loadGuestMatch]);

  const playersById = useMemo(() => new Map((state?.snapshot?.players ?? []).map((player) => [player.id, player])), [state]);
  const teamA = (state?.snapshot?.match.teamA ?? []).map((id) => playersById.get(id)).filter((player): player is GuestPlayer => Boolean(player));
  const teamB = (state?.snapshot?.match.teamB ?? []).map((id) => playersById.get(id)).filter((player): player is GuestPlayer => Boolean(player));
  const unassigned = (state?.snapshot?.players ?? []).filter((player) => player.status === "voy" && !player.team);

  async function leaveMatch() {
    if (!supabase || !state?.snapshotRevision || state.access.status !== "accepted") return;
    setLeaving(true);
    const result = await supabase.rpc("leave_pachanga_guest_match_v1", {
      client_metadata: guestOperationMetadata(),
      expected_snapshot_revision: state.snapshotRevision,
      operation_id: crypto.randomUUID(),
      target_access_id: state.access.id,
    });
    if (result.error) {
      setMessage(result.error.message);
      await loadGuestMatch(state.access.id);
    } else {
      const response = result.data as { access?: GuestAccess } | null;
      setState((current) => current ? { ...current, access: response?.access ?? { ...current.access, status: "revoked" } } : current);
      setMessage("Has abandonado el partido. La plaza queda libre y el acceso se ha cerrado.");
    }
    setConfirmLeave(false);
    setLeaving(false);
  }

  if (!accessId || !supabase) {
    return (
      <main className="guest-match-page">
        <section className="guest-match-state">
          <span>Acceso de invitado</span>
          <h1>No podemos abrir este partido</h1>
          <p>{accessId ? "Supabase no está configurado." : "Falta el acceso confirmado al partido."}</p>
          <div><Link href="/mercado?tab=partidos">Ver partidos públicos</Link><Link href="/">Volver a Pachangas IQ</Link></div>
        </section>
      </main>
    );
  }

  if (loading) return <main className="guest-match-page"><p className="guest-match-state">Cargando partido confirmado...</p></main>;

  if (!state?.snapshot || state.access.status !== "accepted") {
    return (
      <main className="guest-match-page">
        <section className="guest-match-state">
          <span>Acceso de invitado</span>
          <h1>Este partido ya no está disponible para ti</h1>
          <p>{message || "El acceso termina cuando abandonas o dejas de figurar como asistente."}</p>
          <div><Link href="/mercado?tab=partidos">Ver partidos públicos</Link><Link href="/">Volver a Pachangas IQ</Link></div>
        </section>
      </main>
    );
  }

  const match = state.snapshot.match;
  return (
    <main className="guest-match-page">
      <header className="guest-match-header">
        <div>
          <span>Invitado en {state.snapshot.groupName}</span>
          <h1>{match.title}</h1>
          <p>{displayDate(match.date)} · {displayPlace(match.place)}</p>
        </div>
        <div className="guest-live-state"><i /> Sincronizado</div>
      </header>

      <section className="guest-match-summary" aria-label="Estado del partido">
        <div><span>Confirmados</span><strong>{match.confirmedCount}/{match.targetPlayers}</strong></div>
        <div><span>Alineación</span><strong>{match.lineupClosed ? "Cerrada" : "Abierta"}</strong></div>
        <div><span>Modalidad</span><strong>{match.kind || "Fútbol"}</strong></div>
        {match.scoreA !== undefined && match.scoreB !== undefined ? <div><span>Resultado</span><strong>{match.scoreA} - {match.scoreB}</strong></div> : null}
      </section>

      <section className="guest-lineup" aria-label="Alineación del partido">
        <article className="guest-team team-a">
          <header><strong>Equipo 1</strong><span>{teamA.length}</span></header>
          <ul>{teamA.map((player) => <PlayerRow player={player} key={player.id} />)}</ul>
        </article>
        <article className="guest-team team-b">
          <header><strong>Equipo 2</strong><span>{teamB.length}</span></header>
          <ul>{teamB.map((player) => <PlayerRow player={player} key={player.id} />)}</ul>
        </article>
        {unassigned.length ? (
          <article className="guest-team unassigned">
            <header><strong>Por alinear</strong><span>{unassigned.length}</span></header>
            <ul>{unassigned.map((player) => <PlayerRow player={player} key={player.id} />)}</ul>
          </article>
        ) : null}
      </section>

      <section className="guest-access-note">
        <p>Puedes consultar este partido y sus cambios. No tienes acceso al grupo, pagos, teléfonos ni controles de administración.</p>
        {!confirmLeave ? (
          <button type="button" onClick={() => setConfirmLeave(true)}>Abandonar partido</button>
        ) : (
          <div className="guest-leave-confirm" role="alert">
            <strong>¿Seguro que no vas?</strong>
            <p>Tu plaza se liberará y perderás inmediatamente el acceso al partido.</p>
            <button type="button" disabled={leaving} onClick={() => void leaveMatch()}>{leaving ? "Abandonando..." : "Sí, abandonar"}</button>
            <button className="secondary" type="button" disabled={leaving} onClick={() => setConfirmLeave(false)}>Cancelar</button>
          </div>
        )}
        {message ? <p role="status">{message}</p> : null}
      </section>
    </main>
  );
}

export default function GuestMatchPage() {
  return (
    <Suspense fallback={<main className="guest-match-page"><p className="guest-match-state">Cargando partido confirmado...</p></main>}>
      <GuestMatchContent />
    </Suspense>
  );
}
