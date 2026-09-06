"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { PlayerCardView } from "../_components/player-card-view";
import { supabase } from "../supabaseClient";
import { buildTeamRanking, rankingSeason, rankingSortLabels, teamRankingSeasons, type TeamRankingSort } from "./team-ranking-model";
import styles from "./team-ranking.module.css";

export function TeamRanking({ groupId }: { groupId: string }) {
  const [payload, setPayload] = useState<unknown>(null);
  const [status, setStatus] = useState("loading");
  const [attempt, setAttempt] = useState(0);
  const [season, setSeason] = useState(() => rankingSeason(new Date()));
  const [sort, setSort] = useState<TeamRankingSort>("media");
  useEffect(() => {
    const client = supabase;
    let active = true;
    let request = 0;
    const refresh = async () => {
      const current = ++request;
      try {
        if (!client) throw new Error("unavailable");
        const result = await client.from("pachanga_groups").select("id,payload").eq("id", groupId).single();
        if (!active || current !== request) return;
        if (result.error || result.data?.id !== groupId || !Array.isArray(result.data.payload?.players)) throw new Error("unavailable");
        setPayload(result.data.payload);
        setStatus("ready");
      } catch {
        if (active && current === request) { setPayload(null); setStatus("error"); }
      }
    };
    void refresh();
    const channel = client?.channel(`team-ranking-${groupId}`).on("postgres_changes", { event: "UPDATE", schema: "public", table: "pachanga_groups", filter: `id=eq.${groupId}` }, refresh).subscribe();
    const auth = client?.auth.onAuthStateChange(() => queueMicrotask(() => { if (active) void refresh(); }));
    window.addEventListener("focus", refresh);
    window.addEventListener("online", refresh);
    return () => { active = false; if (channel) void client?.removeChannel(channel); auth?.data.subscription.unsubscribe(); window.removeEventListener("focus", refresh); window.removeEventListener("online", refresh); };
  }, [groupId, attempt]);
  const seasons = teamRankingSeasons(payload);
  const activeSeason = seasons.includes(season) ? season : seasons[0];
  const players = buildTeamRanking(payload, activeSeason, sort);
  return <section className={styles.panel} id="ranking" aria-label="Ranking de mi equipo">
    <header><h2>Ranking del equipo</h2><strong>{status === "ready" ? players.length : ""}</strong></header>
    {status === "loading" ? <p role="status">Cargando clasificación del equipo…</p> : status === "error" ? <div role="status"><p>No pudimos cargar el ranking del equipo.</p><button onClick={() => setAttempt(value => value + 1)} type="button">Reintentar</button></div> : <>
      <div className={styles.toolbar}>
        <label>Temporada<select aria-label="Temporada del ranking" value={activeSeason} onChange={event => setSeason(event.target.value)}>{seasons.map(value => <option key={value}>{value}</option>)}</select></label>
        <div><span>Ordenar por</span><div className={styles.sorts}>{Object.entries(rankingSortLabels).map(([key, label]) => <button key={key} type="button" aria-pressed={sort === key} onClick={() => setSort(key as TeamRankingSort)}>{label}</button>)}</div></div>
      </div>
      <div className={styles.grid}>{players.map((player, index) => <Link className={styles.entry} key={player.id} href={`/?grupo=${encodeURIComponent(groupId)}&mobile=perfil&rankingPlayer=${encodeURIComponent(player.id)}`} aria-label={`Abrir ficha de ${player.name} desde ranking`}>
        <PlayerCardView className={`team-mini-player-card ranking-player-card ${player.media <= 64 ? "fifa-card-bronze" : player.media <= 74 ? "fifa-card-silver" : "fifa-card-gold"}`} name={player.name} score={Math.round(player.media)} facets={player.facets} position={player.position} photoSrc={player.avatar} photoStyle={{ objectPosition: `${player.avatarX}% ${player.avatarY}%` }} meta="" featuredBadge={<span className="ranking-card-rank">{index + 1}</span>} />
        <div className={styles.stats}><strong>{sort === "media" ? `Media ${Math.round(player.media)}` : sort === "goles" ? `${player.goals} goles` : sort === "partidos" ? `${player.appearances} PJ` : `${player.wins} victorias`}</strong><dl><div><dt>Goles</dt><dd>{player.goals}</dd></div><div><dt>Partidos</dt><dd>{player.appearances}</dd></div><div><dt>Ganados</dt><dd>{player.wins}</dd></div></dl>{player.inactive ? <small>Ya no está en el grupo</small> : player.injured ? <small>Lesionado</small> : null}</div>
      </Link>)}</div>
      {!players.length ? <p>Todavía no hay jugadores en este equipo.</p> : null}
    </>}
  </section>;
}
