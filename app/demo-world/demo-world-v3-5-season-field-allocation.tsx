"use client";

import { useEffect, useMemo, useState } from "react";
import { seasonVenueMode, seasonVenueStatus } from "../season-venue-allocation-contract";
import {
  assertDemoWorldV35SeasonFieldAllocation,
  type DemoWorldV35Perspective,
  type DemoWorldV35PresentationManifest,
  type DemoWorldV35SeasonFieldAllocation,
} from "./demo-world-v3-5-contract";
import styles from "./demo-world-v3-5-season-field-allocation.module.css";

type Layer = "overview" | "blocks" | "pools" | "automatic" | "hybrid" | "conflicts" | "reservations" | "bindings" | "utilization";

const perspectives: Record<DemoWorldV35Perspective, string> = {
  "club-booking-manager": "Gestor de reservas",
  "league-organizer": "Organizador de Liga",
  "platform-reviewer": "Revisor de plataforma",
  "tournament-organizer": "Organizador de Torneo",
  player: "Jugador",
  referee: "Árbitro",
  "team-owner": "Owner de equipo",
};

const layers: Array<[Layer, string]> = [
  ["overview", "Campos de temporada"], ["blocks", "Bloques recurrentes"],
  ["pools", "Pools"], ["automatic", "Asignación automática"],
  ["hybrid", "Asignación híbrida"], ["conflicts", "Conflictos"],
  ["reservations", "Reservas"], ["bindings", "Bindings"], ["utilization", "Utilización"],
];

function Chip({ children }: { children: string }) {
  return <span className={styles.chip}>{seasonVenueStatus(children)}</span>;
}

function Metric({ label, value }: { label: string; value: number | string }) {
  return <div className={styles.metric}><span>{label}</span><strong>{value}</strong></div>;
}

export function DemoWorldV35SeasonFieldAllocation({ manifest }: { manifest: DemoWorldV35PresentationManifest }) {
  const [data, setData] = useState<DemoWorldV35SeasonFieldAllocation | null>(null);
  const [error, setError] = useState("");
  const [layer, setLayer] = useState<Layer>("overview");
  const [perspective, setPerspective] = useState<DemoWorldV35Perspective>("league-organizer");

  useEffect(() => {
    let active = true;
    void fetch(manifest.seasonFieldAllocation.path, { cache: "force-cache", credentials: "same-origin" })
      .then(async (response) => {
        if (!response.ok) throw new Error("No se pudo cargar la asignación de temporada.");
        return assertDemoWorldV35SeasonFieldAllocation(await response.json() as DemoWorldV35SeasonFieldAllocation);
      })
      .then((value) => { if (active) setData(value); })
      .catch((caught) => { if (active) setError(caught instanceof Error ? caught.message : "Demo V3.5 no disponible."); });
    return () => { active = false; };
  }, [manifest.seasonFieldAllocation.path]);

  const visibleAssignments = useMemo(() => {
    if (!data) return [];
    if (perspective === "player" || perspective === "team-owner") {
      return data.assignments.filter((item) => item.homeTeamId === "synthetic_team_001" || item.awayTeamId === "synthetic_team_001");
    }
    if (perspective === "referee") return data.assignments.filter((item) => item.bindingStatus !== "NONE").slice(0, 16);
    return data.assignments;
  }, [data, perspective]);

  if (error) return <section className={styles.error}><strong>Season Field Allocation no disponible</strong><p>{error}</p></section>;
  if (!data) return <section className={styles.loading} role="status">Cargando asignaciones ficticias de temporada...</section>;

  const selectedPlans = data.plans.filter((plan) => plan.mode === (layer === "automatic" ? "AUTOMATIC" : "HYBRID"));
  return <section className={styles.shell} data-demo-season-allocation="v3.5">
    <header className={styles.hero}><div><span>Mundo Demo V3.5</span><h1>Season Field Allocation</h1><p>128 partidos ficticios, horarios deportivos intactos y publicación canónica de reservas y bindings.</p></div><div className={styles.heroProof}><strong>128</strong><small>partidos</small><strong>0</strong><small>solapes</small><strong>0</strong><small>escrituras</small></div></header>
    <div className={styles.toolbar}><label>Perspectiva<select value={perspective} onChange={(event) => setPerspective(event.target.value as DemoWorldV35Perspective)}>{Object.entries(perspectives).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><nav aria-label="Capas de asignación de temporada">{layers.map(([value, label]) => <button aria-current={layer === value ? "page" : undefined} key={value} onClick={() => setLayer(value)} type="button">{label}</button>)}</nav></div>

    {layer === "overview" ? <><div className={styles.metrics}><Metric label="Bloques" value={data.counts.recurringSeries} /><Metric label="Pools" value={data.counts.pools} /><Metric label="Planes" value={data.counts.plans} /><Metric label="Reservas" value={data.counts.reservations} /><Metric label="Bindings activos" value={data.counts.activeBindings} /><Metric label="Sin campo" value={data.assignments.filter((item) => item.assignmentStatus === "UNASSIGNED").length} /></div><div className={styles.summaryGrid}><article><span>Autoridad</span><h2>RPC real + proyección determinista</h2><p>PostgreSQL temporal, ledger {data.authority.migrationLedger}, con cleanup verificado.</p><Chip>PASS</Chip></article><article><span>Horarios R4B</span><h2>128 de 128 intactos</h2><p>Wave 9B decide Venue/Pitch; nunca desplaza fecha u hora.</p><Chip>CANONICAL</Chip></article><article><span>Privacidad</span><h2>Snapshot público saneado</h2><p>Sin PII, Auth IDs, ubicación privada ni Stripe.</p><Chip>READ ONLY</Chip></article></div></> : null}

    {layer === "blocks" ? <div className={styles.cardGrid}>{data.recurringSeries.map((series) => <article key={series.id}><Chip>{series.status}</Chip><h2>{series.competitionId.replaceAll("_", " ")}</h2><p>{series.frequency} · día {series.weekday} · {series.startDate} → {series.endDate}</p><strong>{series.occurrenceCount} ocurrencias finitas</strong></article>)}</div> : null}

    {layer === "pools" ? <div className={styles.cardGrid}>{data.pools.map((pool) => <article key={pool.id}><Chip>{pool.status}</Chip><h2>{pool.competitionId.replaceAll("_", " ")}</h2><p>Autorización explícita, revisionada y limitada a la competición.</p><strong>{pool.pitchIds.length} Pitches autorizados</strong></article>)}</div> : null}

    {layer === "automatic" || layer === "hybrid" ? <><div className={styles.cardGrid}>{selectedPlans.map((plan) => <article key={plan.id}><Chip>{plan.mode}</Chip><h2>{plan.competitionId.replaceAll("_", " ")}</h2><p>{seasonVenueMode(plan.mode)} · seed {plan.seed}</p><div className={styles.planStats}><b>{plan.assignedMatches} asignados</b><b>{plan.unassignedMatches} sin campo</b><b>{plan.lockCount} locks</b><b>{plan.qualityScore}/100</b></div><small>{plan.resultChecksum.slice(0, 18)}...</small></article>)}</div><div className={styles.assignmentTable}>{visibleAssignments.slice(0, 32).map((item) => <article data-alert={item.assignmentStatus === "UNASSIGNED"} key={item.canonicalMatchId}><div><strong>{item.homeTeamName} vs {item.awayTeamName}</strong><small>{new Date(item.scheduledAfter).toLocaleString("es-ES")} · {item.venueName ?? "Sin campo"} · {item.pitchName ?? "Pendiente"}</small></div><Chip>{item.assignmentStatus}</Chip>{item.lockType ? <b>{item.lockType}</b> : null}</article>)}</div></> : null}

    {layer === "conflicts" ? <div className={styles.cardGrid}>{data.conflicts.map((conflict) => <article data-alert={!conflict.resolved} key={conflict.code}><Chip>{conflict.resolved ? "RESUELTO" : "ACCIÓN REQUERIDA"}</Chip><h2>{conflict.code.replaceAll("_", " ")}</h2><p>{conflict.summary}</p><strong>{conflict.outcome}</strong></article>)}</div> : null}

    {layer === "reservations" || layer === "bindings" ? <><div className={styles.metrics}><Metric label="Reservas canónicas" value={data.counts.reservations} /><Metric label="Bindings activos" value={data.counts.activeBindings} /><Metric label="Canceladas" value={data.assignments.filter((item) => item.reservationStatus === "CANCELLED").length} /><Metric label="Acción requerida" value={data.assignments.filter((item) => item.bindingStatus === "ACTION_REQUIRED").length} /></div><div className={styles.assignmentTable}>{visibleAssignments.filter((item) => layer === "reservations" ? item.reservationStatus !== "NONE" : item.bindingStatus !== "NONE").slice(0, 40).map((item) => <article data-alert={item.bindingStatus === "ACTION_REQUIRED"} key={item.canonicalMatchId}><div><strong>{item.homeTeamName} vs {item.awayTeamName}</strong><small>{item.venueName} · {item.pitchName} · {item.sourceKind}</small></div><Chip>{layer === "reservations" ? item.reservationStatus : item.bindingStatus}</Chip></article>)}</div></> : null}

    {layer === "utilization" ? <div className={styles.utilization}>{data.utilization.map((item) => <article key={item.pitchId}><div><strong>{data.assignments.find((entry) => entry.pitchId === item.pitchId)?.pitchName ?? item.pitchId.replaceAll("_", " ")}</strong><small>{item.assignments} partidos · {item.utilization}% del total</small></div><span><i style={{ width: `${Math.min(100, item.utilization * 5)}%` }} /></span></article>)}</div> : null}

    <footer className={styles.integrity}><span><strong>{data.integrity.matchTimesModified}</strong> horarios alterados</span><span><strong>{data.integrity.confirmedOverlaps}</strong> dobles reservas</span><span><strong>{data.integrity.activeBindingDuplicates}</strong> dobles bindings</span><span><strong>{data.remoteWrites}</strong> writes remotos</span><p>{perspectives[perspective]} · snapshot canónico ficticio</p></footer>
  </section>;
}
