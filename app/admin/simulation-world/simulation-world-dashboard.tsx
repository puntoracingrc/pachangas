"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SyntheticDashboardData } from "../../../simulation/synthetic-world/src/dashboard-data";
import type { SyntheticWorldListItem } from "../../../simulation/synthetic-world/src/store";
import styles from "./simulation-world.module.css";

type DashboardResponse = { data: SyntheticDashboardData | null; worlds: SyntheticWorldListItem[] };
type Tab = "conducta" | "equipos" | "incidencias" | "jugadores" | "partidos" | "ranking" | "resumen" | "salud" | "timeline";

const TABS: Array<{ id: Tab; label: string }> = [
  { id: "resumen", label: "Mundo" },
  { id: "timeline", label: "Timeline" },
  { id: "jugadores", label: "Jugadores" },
  { id: "equipos", label: "Equipos" },
  { id: "partidos", label: "Partidos" },
  { id: "ranking", label: "Ranking" },
  { id: "incidencias", label: "Incidencias" },
  { id: "conducta", label: "Conducta" },
  { id: "salud", label: "System Health" },
];

function shortDate(value: string) {
  return new Intl.DateTimeFormat("es-ES", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "UTC" }).format(new Date(value));
}

function compactNumber(value: number) {
  return new Intl.NumberFormat("es-ES", { notation: value > 9_999 ? "compact" : "standard", maximumFractionDigits: 1 }).format(value);
}

function CountRows({ values }: { values: Record<string, number> }) {
  return (
    <div className={styles.countRows}>
      {Object.entries(values).sort((left, right) => right[1] - left[1]).map(([label, value]) => (
        <div key={label}><span>{label.replaceAll("_", " ")}</span><strong>{compactNumber(value)}</strong></div>
      ))}
    </div>
  );
}

export function SimulationWorldDashboard({
  initialData,
  initialWorlds,
}: {
  initialData: SyntheticDashboardData | null;
  initialWorlds: SyntheticWorldListItem[];
}) {
  const [data, setData] = useState(initialData);
  const [worlds, setWorlds] = useState(initialWorlds);
  const [tab, setTab] = useState<Tab>("resumen");
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [message, setMessage] = useState<string | null>(null);
  const [auto, setAuto] = useState(false);
  const [speed, setSpeed] = useState(2500);
  const [selectedPlayerId, setSelectedPlayerId] = useState(initialData?.players[0]?.id ?? "");
  const [selectedTeamId, setSelectedTeamId] = useState(initialData?.teams[0]?.id ?? "");
  const [selectedMatchId, setSelectedMatchId] = useState(initialData?.matches[0]?.id ?? "");
  const [province, setProvince] = useState("08");
  const [search, setSearch] = useState("");

  const loadWorld = useCallback(async (worldId: string) => {
    setBusy(true);
    busyRef.current = true;
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/simulation-world?world=${encodeURIComponent(worldId)}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`No se pudo cargar el mundo (${response.status})`);
      const payload = await response.json() as DashboardResponse;
      setData(payload.data);
      setWorlds(payload.worlds);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Error cargando el mundo");
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    if (!data && worlds[0] && !busyRef.current) void loadWorld(worlds[0].id);
  }, [data, loadWorld, worlds]);

  const runAction = useCallback(async (step: "day" | "hour" | "month" | "season" | "week") => {
    if (!data || busyRef.current || data.world.status === "completed") return;
    busyRef.current = true;
    setBusy(true);
    setMessage(null);
    try {
      const response = await fetch("/api/admin/simulation-world", {
        body: JSON.stringify({
          action: "advance",
          expectedRevision: data.world.revision,
          operationId: crypto.randomUUID(),
          step,
          worldId: data.world.id,
        }),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      });
      const payload = await response.json() as DashboardResponse & { error?: string };
      if (!response.ok) {
        if (response.status === 409) await loadWorld(data.world.id);
        throw new Error(payload.error === "STALE_WORLD_REVISION" ? "Otro proceso avanzó el mundo; se ha recargado el estado canónico." : payload.error ?? "No se pudo avanzar");
      }
      setData(payload.data);
      setWorlds(payload.worlds);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Error avanzando el mundo");
      setAuto(false);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }, [data, loadWorld]);

  useEffect(() => {
    if (!auto) return;
    const timer = window.setInterval(() => void runAction("day"), speed);
    return () => window.clearInterval(timer);
  }, [auto, runAction, speed]);

  const createWorld = async () => {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    try {
      const response = await fetch("/api/admin/simulation-world", {
        body: JSON.stringify({ action: "create", seed: 20260809 }),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      });
      const payload = await response.json() as DashboardResponse & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "No se pudo crear el mundo");
      setData(payload.data);
      setWorlds(payload.worlds);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Error creando el mundo");
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };

  const selectedPlayer = data?.players.find(({ id }) => id === selectedPlayerId) ?? data?.players[0];
  const selectedTeam = data?.teams.find(({ id }) => id === selectedTeamId) ?? data?.teams[0];
  const selectedMatch = data?.matches.find(({ id }) => id === selectedMatchId) ?? data?.matches[0];
  const filteredTimeline = useMemo(() => {
    if (!data) return [];
    const needle = search.trim().toLowerCase();
    if (!needle) return data.timeline;
    return data.timeline.filter((event) => `${event.eventType} ${event.flow} ${event.actorName}`.toLowerCase().includes(needle));
  }, [data, search]);

  if (!data) {
    return (
      <main className={styles.empty}>
        <p>Pachangas IQ · laboratorio local</p>
        <h1>Synthetic World</h1>
        <span>{worlds.length > 0 ? "Cargando el snapshot canónico…" : "No hay un mundo persistente en esta base local."}</span>
        {worlds.length === 0 ? <button type="button" onClick={() => void createWorld()} disabled={busy}>{busy ? "Creando…" : "Crear mundo · seed 20260809"}</button> : null}
        {message ? <strong>{message}</strong> : null}
      </main>
    );
  }

  const summaryStats = [
    ["Equipos", data.summary.teams], ["Jugadores", data.summary.registeredAgents], ["Partidos", data.summary.totalMatches],
    ["Retos", data.summary.challenges], ["Mercado", data.summary.marketPlayers], ["No disponibles", data.summary.unavailablePlayers],
    ["Notificaciones", data.summary.notifications], ["Cajas", data.summary.boxes], ["Incidencias", data.summary.incidents],
    ["Ataques detectados", data.summary.attacksDetected], ["Posibles no-show", data.summary.possibleNoShows], ["Conducta sin sistema", data.summary.conductScenariosNeedingProduct],
  ] as const;

  return (
    <main className={styles.shell}>
      <header className={styles.header}>
        <div>
          <p>Pachangas IQ · laboratorio local</p>
          <h1>Synthetic World</h1>
        </div>
        <div className={styles.worldMeta}>
          <label>
            <span>Mundo</span>
            <select value={data.world.id} onChange={(event) => void loadWorld(event.target.value)}>
              {worlds.map((world) => <option value={world.id} key={world.id}>{world.name} · r{world.revision}</option>)}
            </select>
          </label>
          <div><span>Fecha virtual</span><strong>{shortDate(data.world.currentDate)}</strong></div>
          <div><span>Temporada</span><strong>{data.world.seasonId.replace("-", "/")}</strong></div>
          <div><span>Revisión</span><strong>{data.world.revision}</strong></div>
        </div>
      </header>

      <section className={styles.clockBar} aria-label="Reloj virtual">
        <strong>{data.world.status === "completed" ? "Temporada completada" : busy ? "Procesando estado oficial…" : auto ? "Auto activo" : "Mundo en pausa"}</strong>
        <div>
          <button type="button" onClick={() => void runAction("hour")} disabled={busy || data.world.status === "completed"}>▶ 1 hora</button>
          <button type="button" onClick={() => void runAction("day")} disabled={busy || data.world.status === "completed"}>▶ 1 día</button>
          <button type="button" onClick={() => void runAction("week")} disabled={busy || data.world.status === "completed"}>▶ 1 semana</button>
          <button type="button" onClick={() => void runAction("month")} disabled={busy || data.world.status === "completed"}>▶ 1 mes</button>
          <button type="button" onClick={() => void runAction("season")} disabled={busy || data.world.status === "completed"}>▶ fin temporada</button>
          <button type="button" className={auto ? styles.activeControl : undefined} onClick={() => setAuto((value) => !value)} disabled={data.world.status === "completed"}>{auto ? "⏸ Pausa" : "Auto"}</button>
          <select aria-label="Velocidad automática" value={speed} onChange={(event) => setSpeed(Number(event.target.value))}>
            <option value={5000}>1 día / 5 s</option>
            <option value={2500}>1 día / 2,5 s</option>
            <option value={1000}>1 día / 1 s</option>
          </select>
        </div>
      </section>
      {message ? <p className={styles.message}>{message}</p> : null}

      <nav className={styles.tabs} aria-label="Secciones del mundo">
        {TABS.map((item) => <button type="button" key={item.id} className={tab === item.id ? styles.activeTab : undefined} onClick={() => setTab(item.id)}>{item.label}</button>)}
      </nav>

      <div className={styles.content}>
        {tab === "resumen" ? (
          <>
            <section className={styles.statGrid}>
              {summaryStats.map(([label, value]) => <article key={label}><span>{label}</span><strong>{compactNumber(value)}</strong></article>)}
            </section>
            <section className={styles.twoColumns}>
              <div className={styles.panel}>
                <header><div><span>Top Barcelona</span><h2>Season Score</h2></div><b>55 / 30 / 15</b></header>
                <ol className={styles.rankingList}>
                  {data.ranking.filter(({ provinceCode }) => provinceCode === "08").slice(0, 11).map((row) => (
                    <li key={row.agentId}><b>{row.rank}</b><span>{row.displayName}</span><strong>{row.score.toFixed(1)}</strong><i>{row.movement > 0 ? `↑${row.movement}` : row.movement < 0 ? `↓${Math.abs(row.movement)}` : "="}</i></li>
                  ))}
                </ol>
              </div>
              <div className={styles.panel}>
                <header><div><span>Snapshots</span><h2>Historia inmutable</h2></div><b>{data.snapshots.length}</b></header>
                <div className={styles.snapshotList}>
                  {data.snapshots.slice(0, 12).map((snapshot) => <div key={snapshot.id}><strong>{snapshot.kind}</strong><span>{shortDate(snapshot.virtualDate)}</span><b>r{snapshot.revision} · seq {snapshot.serverSequence}</b></div>)}
                  {data.snapshots.length === 0 ? <p>Aún no hay snapshots.</p> : null}
                </div>
              </div>
            </section>
          </>
        ) : null}

        {tab === "timeline" ? (
          <section className={styles.panel}>
            <header><div><span>Últimos eventos canónicos</span><h2>Timeline</h2></div><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar flujo, actor o evento" /></header>
            <div className={styles.timeline}>
              {filteredTimeline.map((event) => <article key={`${event.sequence}-${event.operationId}`}><time>{shortDate(event.virtualDate)}</time><div><strong>{event.eventType.replaceAll("_", " ")}</strong><span>{event.actorName} · {event.flow}</span></div><b className={styles[event.status]}>{event.status}</b><small>#{event.sequence}</small></article>)}
            </div>
          </section>
        ) : null}

        {tab === "jugadores" && selectedPlayer ? (
          <section className={styles.inspector}>
            <aside><label><span>Jugador sintético</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Filtrar jugadores" /></label><select size={18} value={selectedPlayer.id} onChange={(event) => setSelectedPlayerId(event.target.value)}>{data.players.filter(({ displayName }) => displayName.toLowerCase().includes(search.toLowerCase())).map((player) => <option key={player.id} value={player.id}>{player.displayName} · {player.city}</option>)}</select></aside>
            <div className={styles.detail}>
              <header><div><span>{selectedPlayer.kind} · {selectedPlayer.city}</span><h2>{selectedPlayer.displayName}</h2></div><strong>{selectedPlayer.ratingV2.toFixed(1)} GRL</strong></header>
              <div className={styles.detailGrid}><div><span>Perfil</span><b>{selectedPlayer.position} · {selectedPlayer.status}</b></div><div><span>Fiabilidad</span><b>{Math.round(selectedPlayer.ratingReliability * 100)}%</b></div><div><span>Ranking</span><b>{selectedPlayer.ranking ? `#${selectedPlayer.ranking.rank} · ${selectedPlayer.ranking.score.toFixed(1)}` : "Sin ranking"}</b></div><div><span>Integrity</span><b>{selectedPlayer.integrityRisk.toFixed(2)} · {selectedPlayer.attackProfile}</b></div></div>
              <h3>Facetas</h3><div className={styles.facets}>{Object.entries(selectedPlayer.facets).map(([name, value]) => <div key={name}><span>{name}</span><strong>{value.toFixed(1)}</strong><i style={{ width: `${value}%` }} /></div>)}</div>
              <div className={styles.threeColumns}><div><h3>Equipos</h3>{selectedPlayer.teams.map((team) => <p key={team.id}>{team.name}</p>)}</div><div><h3>Actividad</h3><p>{selectedPlayer.achievements} logros · {selectedPlayer.boxes} cajas</p><p>{selectedPlayer.notifications} notificaciones</p></div><div><h3>Asistencia</h3><CountRows values={selectedPlayer.attendance} /></div></div>
            </div>
          </section>
        ) : null}

        {tab === "equipos" && selectedTeam ? (
          <section className={styles.inspector}>
            <aside><span>50 equipos sintéticos</span><select size={20} value={selectedTeam.id} onChange={(event) => setSelectedTeamId(event.target.value)}>{data.teams.map((team) => <option key={team.id} value={team.id}>{team.name} · {team.playerCount}</option>)}</select></aside>
            <div className={styles.detail}><header><div><span>{selectedTeam.city} · {selectedTeam.modality}</span><h2>{selectedTeam.name}</h2></div><strong>{selectedTeam.strength.toFixed(1)}</strong></header><div className={styles.detailGrid}><div><span>Owner</span><b>{selectedTeam.ownerName}</b></div><div><span>Admins</span><b>{selectedTeam.adminNames.join(", ")}</b></div><div><span>Identidad</span><b>{selectedTeam.style} · {selectedTeam.activity}</b></div><div><span>Mercado / retos</span><b>{selectedTeam.marketPolicy} · {selectedTeam.challengePolicy}</b></div></div><h3>Plantilla</h3><div className={styles.roster}>{selectedTeam.playerNames.map((name) => <span key={name}>{name}</span>)}</div><p className={styles.muted}>Logical cluster: {selectedTeam.integrityClusterId}</p></div>
          </section>
        ) : null}

        {tab === "partidos" && selectedMatch ? (
          <section className={styles.inspector}>
            <aside><span>{data.matches.length} partidos</span><select size={20} value={selectedMatch.id} onChange={(event) => setSelectedMatchId(event.target.value)}>{data.matches.map((match) => <option key={match.id} value={match.id}>{shortDate(match.occurredAt)} · {match.homeTeam}</option>)}</select></aside>
            <div className={styles.detail}><header><div><span>{selectedMatch.kind} · {selectedMatch.state}</span><h2>{selectedMatch.homeTeam} · {selectedMatch.awayTeam}</h2></div><strong>{selectedMatch.result ?? "Pendiente"}</strong></header><div className={styles.detailGrid}><div><span>Fecha</span><b>{shortDate(selectedMatch.occurredAt)}</b></div><div><span>Participantes</span><b>{selectedMatch.participantCount} + {selectedMatch.guestCount} invitados</b></div><div><span>Confidence</span><b>{selectedMatch.confidence.toFixed(2)}</b></div><div><span>Season Score</span><b>{selectedMatch.evidenceExcluded ? "Evidencia excluida" : "Evidencia válida"}</b></div></div><h3>Goleadores</h3><div className={styles.roster}>{selectedMatch.scorers.map((scorer) => <span key={scorer.name}>{scorer.name} · {scorer.goals}</span>)}{selectedMatch.scorers.length === 0 ? <span>Sin resultado confirmado</span> : null}</div></div>
          </section>
        ) : null}

        {tab === "ranking" ? (
          <section className={styles.panel}><header><div><span>Top 50 territorial</span><h2>Season Score V3</h2></div><select value={province} onChange={(event) => setProvince(event.target.value)}>{[...new Set(data.ranking.map(({ provinceCode }) => provinceCode))].map((code) => <option key={code} value={code}>Provincia {code}</option>)}</select></header><ol className={styles.rankingList}>{data.ranking.filter(({ provinceCode }) => provinceCode === province).slice(0, 50).map((row) => <li key={row.agentId}><b>{row.rank}</b><span>{row.displayName}<small>{row.certification} · {row.validChallenges} retos · {row.logicalOpponents} rivales</small></span><strong>{row.score.toFixed(1)}</strong><i>{row.movement > 0 ? `↑${row.movement}` : row.movement < 0 ? `↓${Math.abs(row.movement)}` : "="}</i></li>)}</ol></section>
        ) : null}

        {tab === "incidencias" ? (
          <section className={styles.panel}><header><div><span>Registro permanente</span><h2>Incidencias</h2></div><b>{data.incidents.length}</b></header><div className={styles.incidents}>{data.incidents.map((incident) => <article key={incident.id} className={styles[incident.severity]}><header><strong>{incident.category}</strong><b>{incident.status}</b></header><h3>{incident.operation}</h3><p>{String(incident.actual.behavior ?? incident.actual.productCapability ?? "Ver expected/actual")}</p><div><span>{shortDate(incident.virtualDate)}</span><span>{incident.actorName ?? "Sistema"}</span><span>{incident.occurrenceCount} ocurrencias</span></div><details><summary>Expected / actual / reproducción</summary><pre>{JSON.stringify({ actual: incident.actual, expected: incident.expected, reproduction: incident.reproductionSteps, resolution: incident.resolution }, null, 2)}</pre></details></article>)}</div></section>
        ) : null}

        {tab === "conducta" ? (
          <section className={styles.twoColumns}>
            <div className={styles.panel}><header><div><span>Asistencia</span><h2>Cancelación no es no-show</h2></div><b>{data.summary.possibleNoShows}</b></header><CountRows values={data.attendance} /><p className={styles.muted}>{data.summary.possibleRepeatNoShowAgents} agentes con dos o más posibles no-show. La base actual no permite confirmarlos canónicamente.</p></div>
            <div className={styles.panel}><header><div><span>Conducta</span><h2>Sistema de reportes</h2></div><b className={styles.warning}>NOT IMPLEMENTED</b></header><CountRows values={data.conduct.byKind} /><p className={styles.muted}>{data.conduct.needsProduct} incidentes habrían requerido denuncias generales. {data.conduct.implementedGuestReviews} usaron el flujo real disponible de revisión de abandono de invitado. No se aplicaron sanciones ni cambios de Rating V2.</p></div>
            <div className={styles.panel}><header><div><span>Notificaciones</span><h2>Tipos observados</h2></div><b>{Object.keys(data.notifications).length}</b></header><CountRows values={data.notifications} /></div>
            <div className={styles.panel}><header><div><span>Decisiones pendientes</span><h2>Producto</h2></div></header><ul className={styles.decisionList}><li>Distinguir cancelación de no-show mediante cierre de asistencia.</li><li>Definir relación deportiva válida para denunciar.</li><li>Ponderar fuentes independientes frente a campañas de un grupo.</li><li>Crear revisión, apelación y restricciones sin tocar Rating V2.</li></ul></div>
          </section>
        ) : null}

        {tab === "salud" ? (
          <section className={styles.panel}><header><div><span>Cobertura viva</span><h2>System Health</h2></div><b>{data.coverage.length} flujos</b></header><div className={styles.healthGrid}>{data.health.map((row) => <article key={row.area}><strong>{row.area}</strong><b className={styles[row.status.toLowerCase()]}>{row.status}</b><span>{compactNumber(row.executions)} ejecuciones · {row.failures} fallos</span></article>)}</div><h3>Matriz de cobertura</h3><div className={styles.coverageTable}>{data.coverage.map((row) => <div key={`${row.flow}-${row.scenario}`}><strong>{row.flow}</strong><span>{row.scenario}</span><b className={styles[row.status.toLowerCase().replace("no_coverage", "untested")]}>{row.status}</b><small>{row.timesExecuted}× · {row.failures} fallos</small></div>)}</div></section>
        ) : null}
      </div>
      <footer className={styles.labFooter}><span>Seed {data.world.seed} · base {data.world.sourceCommit.slice(0, 12)}</span><strong>LOCAL ONLY · sin producción</strong></footer>
    </main>
  );
}
