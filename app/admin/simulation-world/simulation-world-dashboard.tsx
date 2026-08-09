"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SyntheticDashboardData } from "../../../simulation/synthetic-world/src/dashboard-data";
import type { SyntheticWorldListItem } from "../../../simulation/synthetic-world/src/store";
import styles from "./simulation-world.module.css";

type DashboardResponse = { data: SyntheticDashboardData | null; worlds: SyntheticWorldListItem[] };
type Tab = "conducta" | "equipos" | "incidencias" | "jugadores" | "network_health" | "partidos" | "ranking" | "ranking_funnel" | "resumen" | "salud" | "timeline";

const TABS: Array<{ id: Tab; label: string }> = [
  { id: "resumen", label: "Mundo" },
  { id: "timeline", label: "Timeline" },
  { id: "jugadores", label: "Jugadores" },
  { id: "equipos", label: "Equipos" },
  { id: "partidos", label: "Partidos" },
  { id: "ranking", label: "Ranking" },
  { id: "ranking_funnel", label: "Ranking funnel" },
  { id: "network_health", label: "Network Health" },
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

function readable(value: string) {
  return value.replaceAll("_", " ");
}

function RankingFunnelView({ data }: { data: SyntheticDashboardData }) {
  const audit = data.rankingFunnel;
  const [playerSearch, setPlayerSearch] = useState("");
  const [playerId, setPlayerId] = useState(audit.topCandidates[0]?.playerId ?? audit.players[0]?.id ?? "");
  const player = audit.players.find(({ id }) => id === playerId) ?? audit.players[0];
  const traces = audit.evidenceTraces.filter(({ agentId }) => agentId === player?.id)
    .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt));
  const [traceId, setTraceId] = useState("");
  const trace = traces.find(({ matchId }) => matchId === traceId) ?? traces[0];
  const visiblePlayers = audit.players.filter(({ displayName, id }) => `${displayName} ${id}`.toLowerCase().includes(playerSearch.toLowerCase()));
  return (
    <div className={styles.funnelView}>
      <section className={styles.statGrid}>
        <article><span>Registrados</span><strong>{audit.totals.registered}</strong></article>
        <article><span>Ranking eligible</span><strong>{audit.totals.rankingEligible}</strong></article>
        <article><span>Trofeo eligible</span><strong>{audit.totals.trophyEligible}</strong></article>
        <article><span>Eligible orgánico</span><strong>{audit.totals.organicEligible}</strong></article>
        <article><span>Pending integrity</span><strong>{audit.totals.pendingIntegrityReview}</strong></article>
        <article><span>Source sin evidence</span><strong>{audit.evidence.sourceMatchesWithoutEvidence.length}</strong></article>
      </section>

      <section className={styles.auditColumns}>
        <div className={styles.panel}>
          <header><div><span>640 jugadores</span><h2>Embudo completo</h2></div><b>{audit.totals.trophyEligible}</b></header>
          <div className={styles.funnelRows}>
            {audit.funnel.map((row, index) => <div key={`${index}-${row.label}`}><span>{row.label}<small>{row.percentage}% · pérdida {row.lossFromPrevious}</small></span><i><b style={{ width: `${Math.max(1, row.percentage)}%` }} /></i><strong>{row.count}</strong></div>)}
          </div>
        </div>
        <div className={styles.panel}>
          <header><div><span>No secuencial</span><h2>Blockers e interacciones</h2></div><b>{audit.gates.rankedPopulation}</b></header>
          <div className={styles.gateRows}>
            {audit.gates.gates.map((row) => <div key={row.gate}><span>{readable(row.gate)}<small>solo {row.failedOnlyThisGate} · con otros {row.failedThisAndOthers}</small></span><strong>{row.totalFailed}</strong></div>)}
          </div>
          <h3>Leave-one-gate-out</h3>
          <div className={styles.inlineMetrics}>{audit.gates.leaveOneOut.map((row) => <span key={row.removedGate}><small>{readable(row.removedGate)}</small><b>{row.certificable}</b></span>)}</div>
        </div>
      </section>

      <section className={styles.auditColumns}>
        <div className={styles.panel}>
          <header><div><span>Unidad correcta</span><h2>Evidencia Season Score</h2></div><b>{compactNumber(audit.evidence.playerMatchAccepted)}</b></header>
          <div className={styles.metricRows}>
            <div><span>Partidos de Reto</span><strong>{audit.evidence.matchLevelChallengeEvidence}</strong></div>
            <div><span>Partidos marcados válidos</span><strong>{audit.evidence.matchLevelMarkedValid}</strong></div>
            <div><span>Player-match fuente</span><strong>{compactNumber(audit.evidence.playerMatchSource)}</strong></div>
            <div><span>Aceptadas por B</span><strong>{compactNumber(audit.evidence.playerMatchAccepted)}</strong></div>
            <div><span>Excluidas por B</span><strong>{compactNumber(audit.evidence.excludedPlayerMatchEvidence)}</strong></div>
          </div>
          <h3>Motivos de exclusión, multi-label</h3>
          <div className={styles.gateRows}>{audit.evidence.excludedByReason.map((row) => <div key={row.reason}><span>{readable(row.reason)}<small>{row.affectedPlayers} jugadores</small></span><strong>{row.evidence}</strong></div>)}</div>
        </div>
        <div className={styles.panel}>
          <header><div><span>Retención C</span><h2>Atacante vs legítimo</h2></div><b>{audit.totals.pendingIntegrityReview}</b></header>
          <div className={styles.confusionMatrix}>
            <span /><b>HOLD</b><b>NO HOLD</b>
            <strong>Atacante</strong><i>{audit.integrity.confusionAllRegistered.truePositive}</i><i>{audit.integrity.confusionAllRegistered.falseNegative}</i>
            <strong>Legítimo</strong><i>{audit.integrity.confusionAllRegistered.falsePositive}</i><i>{audit.integrity.confusionAllRegistered.trueNegative}</i>
          </div>
          <h3>Motivos pending</h3>
          <CountRows values={audit.integrity.pendingByReason} />
        </div>
      </section>

      <section className={styles.auditColumns}>
        <div className={styles.panel}>
          <header><div><span>Team ID frente a identidad canónica</span><h2>Rivales por jugador</h2></div><b>{audit.opponents.collapseRows.length} colapsos</b></header>
          <div className={styles.counterfactualTable}>
            {audit.opponents.technicalDistribution.map((row, index) => <div key={row.label}><b>{row.label}</b><span>Rivales distintos<small>mismo tramo</small></span><strong>{row.total} team IDs</strong><strong>{audit.opponents.logicalDistribution[index]?.total ?? 0} lógicos</strong></div>)}
          </div>
        </div>
        <div className={styles.panel}>
          <header><div><span>Hyperactive a low activity</span><h2>Actividad y elegibilidad</h2></div><b>{audit.density.months} meses</b></header>
          <div className={styles.gateRows}>
            {audit.density.activityScenarios.map((row) => <div key={row.classification}><span>{readable(row.classification)}<small>{row.count} jugadores · trofeo {row.trophyEligiblePercentage}%</small></span><strong>{row.rankingEligiblePercentage}% ranking</strong></div>)}
          </div>
        </div>
      </section>

      <section className={styles.panel}>
        <header><div><span>Comparación territorial</span><h2>Provincias</h2></div><b>medianas</b></header>
        <div className={styles.counterfactualTable}>
          {audit.provinceComparison.map((row) => <div key={row.provinceCode}><b>{row.provinceCode}</b><span>{row.registered} jugadores<small>{row.medianChallenges} retos · {row.medianLogicalOpponents} rivales · conf. {row.medianConfidence} · div. {row.medianDiversity}</small></span><strong>{row.rankingEligible} ranking</strong><strong>{row.trophyEligible} trofeo</strong><i>{row.pendingIntegrityReview} pending</i></div>)}
        </div>
      </section>

      {player ? (
        <section className={styles.inspector}>
          <aside>
            <label><span>Filtro de jugador</span><input value={playerSearch} onChange={(event) => setPlayerSearch(event.target.value)} placeholder="Nombre o ID" /></label>
            <select size={18} value={player.id} onChange={(event) => { setPlayerId(event.target.value); setTraceId(""); }}>
              {visiblePlayers.map((item) => <option key={item.id} value={item.id}>{item.displayName} · {item.sourceChallengeEvidence}</option>)}
            </select>
          </aside>
          <div className={styles.detail}>
            <header><div><span>{player.persona} · {player.attackProfile}</span><h2>{player.displayName}</h2></div><strong>{player.score.toFixed(1)}</strong></header>
            <div className={styles.detailGrid}>
              <div><span>Retos fuente / válidos</span><b>{player.sourceChallengeEvidence} / {player.acceptedEvidence}</b></div>
              <div><span>Team IDs / lógicos</span><b>{player.sourceTechnicalOpponents} / {player.sourceLogicalOpponents}</b></div>
              <div><span>Confidence / diversity</span><b>{player.competitiveConfidence.toFixed(2)} / {player.competitionNetworkDiversity.toFixed(2)}</b></div>
              <div><span>Ranking / trofeo</span><b>{player.rankingEligible ? `#${player.provinceRank}` : "fuera"} · {player.certification}</b></div>
            </div>
            <h3>Blockers</h3><p className={styles.muted}>{player.certificationReasons.map(readable).join(" · ") || "Sin bloqueos"}</p>
            <div className={styles.traceLayout}>
              <div className={styles.traceList}>
                {traces.map((item) => <button type="button" key={`${item.matchId}-${item.agentId}`} className={item.accepted ? styles.traceAccepted : styles.traceExcluded} onClick={() => setTraceId(item.matchId)}><span>{shortDate(item.occurredAt)}<small>{item.matchId.slice(0, 8)} · {readable(item.rule)}</small></span><b>{item.matchCompetitiveConfidence.toFixed(2)}</b></button>)}
                {traces.length === 0 ? <p>Sin Retos confirmados.</p> : null}
              </div>
              {trace ? <div className={styles.traceDetail}><span>Trace de Reto</span><h3>{trace.matchId}</h3><p>{trace.accepted ? "Cuenta como evidencia" : "No cuenta"} · {trace.exclusionReasons.map(readable).join(", ") || "B accepted"}</p><div className={styles.metricRows}><div><span>Match confidence</span><strong>{trace.matchCompetitiveConfidence.toFixed(3)}</strong></div><div><span>Independencia</span><strong>{trace.opponentIndependence.toFixed(3)}</strong></div><div><span>Peso</span><strong>{trace.confidenceWeight.toFixed(3)}</strong></div><div><span>Rival lógico</span><strong>{trace.logicalOpponentId}</strong></div></div><details><summary>Componentes exactos</summary><pre>{JSON.stringify(trace.confidenceBreakdown, null, 2)}</pre></details></div> : null}
            </div>
          </div>
        </section>
      ) : null}

      <section className={styles.panel}>
        <header><div><span>Solo clones</span><h2>Contrafactuales A–E</h2></div><b>V1 intacto</b></header>
        <div className={styles.counterfactualTable}>
          {data.rankingCounterfactuals.map((row) => <div key={row.id}><b>{row.id}</b><span>{row.label}<small>{row.addedMatches} partidos añadidos · {row.worldId.slice(0, 8)}</small></span><strong>{row.totals.rankingEligible} ranking</strong><strong>{row.totals.trophyEligible} trofeo</strong><i>{row.totals.pendingIntegrityReview} pending</i></div>)}
        </div>
      </section>

      <section className={styles.panel}>
        <header><div><span>Mayor Season Score</span><h2>Top 50 candidatos</h2></div><b>No implica trofeo</b></header>
        <ol className={styles.rankingList}>{audit.topCandidates.map((row) => <li key={row.playerId} onClick={() => setPlayerId(row.playerId)}><b>{row.rank}</b><span>{row.displayName}<small>{row.certification} · {row.validChallenges} retos · {row.logicalOpponents} rivales · {row.certificationBlockers.map(readable).join(", ")}</small></span><strong>{row.score.toFixed(1)}</strong><i>{row.provinceRank ? `#${row.provinceRank}` : "—"}</i></li>)}</ol>
      </section>
    </div>
  );
}

function NetworkHealthView({ data }: { data: SyntheticDashboardData }) {
  const audit = data.networkHealthV31;
  const nodeById = new Map(audit.graph.nodes.map((node) => [node.id, node]));
  const healthySizes = audit.ecosystems.filter(({ scenario }) => scenario === "healthy");
  return (
    <div className={styles.networkHealthView}>
      <section className={styles.statGrid}>
        <article><span>Candidato aceptado</span><strong>{audit.candidateAccepted ? "Sí" : "No"}</strong></article>
        <article><span>Referencia</span><strong>M3</strong></article>
        <article><span>Ranking V1</span><strong>{audit.v31Clone.rankingEligible}</strong></article>
        <article><span>Candidatos 25/10</span><strong>{audit.v31Clone.trophyCandidates}</strong></article>
        <article><span>HOLD referencia</span><strong>{audit.v31Clone.pending}</strong></article>
        <article><span>Top10 territorial</span><strong>{(audit.v31Clone.top10Contamination * 100).toFixed(1)}%</strong></article>
      </section>

      <section className={styles.networkHealthColumns}>
        <div className={styles.panel}>
          <header><div><span>Provincia {audit.graph.provinceCode}</span><h2>Red competitiva</h2></div><b>{audit.graph.nodes.length} equipos</b></header>
          <div className={styles.networkGraph}>
            <svg viewBox="0 0 100 100" role="img" aria-label="Grafo de equipos y Retos de la provincia 08">
              {audit.graph.edges.map((edge) => {
                const source = nodeById.get(edge.source);
                const target = nodeById.get(edge.target);
                if (!source || !target) return null;
                return <line key={`${edge.source}-${edge.target}`} x1={source.x} y1={source.y} x2={target.x} y2={target.y} opacity={Math.min(0.75, 0.18 + edge.matches * 0.08)} />;
              })}
              {audit.graph.nodes.map((node) => (
                <g key={node.id} className={node.possibleRing ? styles.networkRingNode : node.hold ? styles.networkHoldNode : node.topCandidate ? styles.networkTopNode : undefined}>
                  <circle cx={node.x} cy={node.y} r={node.topCandidate ? 2.8 : 2.2} />
                  <title>{node.label} · {node.degree} conexiones{node.hold ? " · HOLD" : ""}</title>
                </g>
              ))}
            </svg>
            <div className={styles.networkLegend}><span>Equipo</span><span>Top candidato</span><span>HOLD</span><span>Ring posible</span></div>
          </div>
          <p className={styles.muted}>Las líneas representan Retos confirmados. La conexión entre clubes es saludable por defecto; el color señala contexto para inspección, nunca culpabilidad.</p>
        </div>

        <div className={styles.panel}>
          <header><div><span>Mundo V1 · revisión {audit.source.revision}</span><h2>Comparación M0–M5</h2></div><b>{audit.recommendedCandidate ?? "Sin candidato"}</b></header>
          <div className={styles.networkModelTable}>
            {audit.modelMetrics.map((row) => (
              <div key={`${row.modelId}-${row.threshold ?? "base"}`}>
                <strong>{row.modelId.replace("model_", "M").replaceAll("_", " ")}{row.threshold === undefined ? "" : ` · ${row.threshold}`}</strong>
                <span>{row.certifiable} certificables</span>
                <span>FPR {(row.falsePositiveRate * 100).toFixed(1)}%</span>
                <span>Top10 cert. {(row.certifiedTop10Contamination * 100).toFixed(1)}%</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className={styles.networkHealthColumns}>
        <div className={styles.panel}>
          <header><div><span>30 semillas por tamaño</span><h2>Efecto del ecosistema</h2></div><b>V3 0,68</b></header>
          <div className={styles.ecosystemBars}>
            {healthySizes.map((row) => (
              <div key={row.teamCount}>
                <strong>{row.teamCount}</strong>
                <span><i style={{ width: `${Math.min(100, row.v3MedianDiversity * 100)}%` }} /></span>
                <b>{row.v3MedianDiversity.toFixed(3)}</b>
                <small>FPR {(row.models.model_0_v3.falsePositiveRate * 100).toFixed(1)}%</small>
              </div>
            ))}
          </div>
        </div>
        <div className={styles.panel}>
          <header><div><span>Entrega de premios</span><h2>Readiness territorial</h2></div><b>25 / 10 intacto</b></header>
          <div className={styles.readinessTable}>
            {audit.provinceReadiness.map((row) => <div key={row.provinceCode}><strong>{row.provinceCode}</strong><span>{row.activeTeams} equipos · {row.rankingEligible} ranking · {row.certifiable} certificables</span><b>{readable(row.state)}</b></div>)}
          </div>
          <p className={styles.networkDecision}>Producto V3: sin cambios. La señal absoluta depende del tamaño, pero ningún reemplazo ha demostrado aún protección y falso positivo suficientes sobre V1.</p>
        </div>
      </section>
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

        {tab === "ranking_funnel" ? <RankingFunnelView key={data.world.id} data={data} /> : null}

        {tab === "network_health" ? <NetworkHealthView data={data} /> : null}

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
