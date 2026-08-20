"use client";

import { useMemo, useState } from "react";
import {
  DataTable,
  EmptyState,
  Metric,
  MetricGrid,
  Panel,
  StatusBadge,
  formatAdminDate,
} from "../_components/platform-ui";
import styles from "../platform-admin.module.css";

type JsonRecord = Record<string, unknown>;

type RankingSeason = {
  candidateChecksum: string | null;
  candidateCount: number;
  eligiblePlayers: number;
  endsAt: string;
  id: string;
  key: string;
  label: string;
  lastErrorCode: string | null;
  lastRefreshAt: string | null;
  notEligiblePlayers: number;
  pendingIntegrityPlayers: number;
  publishedRevision: number;
  rankingRevision: number;
  rebuildId: string | null;
  rebuildState: string | null;
  revision: number;
  startsAt: string;
  status: string;
};

type IntegrityReview = {
  createdAt: string;
  evidenceSummary: JsonRecord;
  id: string;
  playerName: string;
  provinceCode: string;
  reasonCodes: string[];
  reference: string;
  revision: number;
  riskClassification: string;
  riskScore: number;
  seasonLabel: string;
};

type QueueItem = {
  attempts: number;
  availableAt: string;
  errorCode: string | null;
  id: string;
  reason: string;
  scope: string;
  seasonLabel: string;
  sourceType: string;
  state: string;
};

type VenueMapping = {
  confidence: number;
  effectiveFrom: string;
  placeId: string;
  provinceCode: string;
  revision: number;
  source: string;
};

type RankingOverview = {
  formula: { checksum: string; configuration: JsonRecord; key: string; version: number } | null;
  health: { metrics: JsonRecord; reasonCodes: string[]; status: string };
  integrity: { approved: number; excluded: number; pending: number };
  integrityReviews: IntegrityReview[];
  invariants: { awardsEnabled: boolean; conductAffectsScore: boolean; ratingV2ReadOnly: boolean; rewardsAffectScore: boolean };
  queue: { deadLetter: number; failed: number; processing: number; queued: number };
  queueItems: QueueItem[];
  seasons: RankingSeason[];
  settings: {
    pilotProvinceCodes: string[];
    provincialAwardsEnabled: boolean;
    provincialRankingsEnabled: boolean;
    revision: number;
    seasonScoreEnabled: boolean;
  };
  venueMappings: VenueMapping[];
};

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function rows(value: unknown) {
  return Array.isArray(value) ? value.map(record) : [];
}

function normalizeOverview(value: unknown): RankingOverview {
  const root = record(value);
  const settings = record(root.settings);
  const queue = record(root.queue);
  const integrity = record(root.integrity);
  const invariants = record(root.invariants);
  const health = record(root.health);
  const formula = Object.keys(record(root.formula)).length ? record(root.formula) : null;
  return {
    formula: formula ? {
      checksum: String(formula.checksum ?? ""),
      configuration: record(formula.configuration),
      key: String(formula.key ?? ""),
      version: Number(formula.version) || 0,
    } : null,
    health: {
      metrics: record(health.metrics),
      reasonCodes: Array.isArray(health.reasonCodes) ? health.reasonCodes.map(String) : [],
      status: String(health.status ?? "UNKNOWN"),
    },
    integrity: {
      approved: Number(integrity.approved) || 0,
      excluded: Number(integrity.excluded) || 0,
      pending: Number(integrity.pending) || 0,
    },
    integrityReviews: rows(root.integrityReviews).map((item) => ({
      createdAt: String(item.createdAt ?? ""),
      evidenceSummary: record(item.evidenceSummary),
      id: String(item.id ?? ""),
      playerName: String(item.playerName ?? "Jugador"),
      provinceCode: String(item.provinceCode ?? "00"),
      reasonCodes: Array.isArray(item.reasonCodes) ? item.reasonCodes.map(String) : [],
      reference: String(item.reference ?? ""),
      revision: Number(item.revision) || 1,
      riskClassification: String(item.riskClassification ?? "watch"),
      riskScore: Number(item.riskScore) || 0,
      seasonLabel: String(item.seasonLabel ?? "Temporada"),
    })),
    invariants: {
      awardsEnabled: Boolean(invariants.awardsEnabled),
      conductAffectsScore: Boolean(invariants.conductAffectsScore),
      ratingV2ReadOnly: Boolean(invariants.ratingV2ReadOnly),
      rewardsAffectScore: Boolean(invariants.rewardsAffectScore),
    },
    queue: {
      deadLetter: Number(queue.deadLetter) || 0,
      failed: Number(queue.failed) || 0,
      processing: Number(queue.processing) || 0,
      queued: Number(queue.queued) || 0,
    },
    queueItems: rows(root.queueItems).map((item) => ({
      attempts: Number(item.attempts) || 0,
      availableAt: String(item.availableAt ?? ""),
      errorCode: typeof item.errorCode === "string" ? item.errorCode : null,
      id: String(item.id ?? ""),
      reason: String(item.reason ?? ""),
      scope: String(item.scope ?? "season"),
      seasonLabel: String(item.seasonLabel ?? "Temporada"),
      sourceType: String(item.sourceType ?? "manual"),
      state: String(item.state ?? "queued"),
    })),
    seasons: rows(root.seasons).map((item) => ({
      candidateChecksum: typeof item.candidateChecksum === "string" ? item.candidateChecksum : null,
      candidateCount: Number(item.candidateCount) || 0,
      eligiblePlayers: Number(item.eligiblePlayers) || 0,
      endsAt: String(item.endsAt ?? ""),
      id: String(item.id ?? ""),
      key: String(item.key ?? ""),
      label: String(item.label ?? "Temporada"),
      lastErrorCode: typeof item.lastErrorCode === "string" ? item.lastErrorCode : null,
      lastRefreshAt: typeof item.lastRefreshAt === "string" ? item.lastRefreshAt : null,
      notEligiblePlayers: Number(item.notEligiblePlayers) || 0,
      pendingIntegrityPlayers: Number(item.pendingIntegrityPlayers) || 0,
      publishedRevision: Number(item.publishedRevision) || 0,
      rankingRevision: Number(item.rankingRevision) || 0,
      rebuildId: typeof item.rebuildId === "string" ? item.rebuildId : null,
      rebuildState: typeof item.rebuildState === "string" ? item.rebuildState : null,
      revision: Number(item.revision) || 1,
      startsAt: String(item.startsAt ?? ""),
      status: String(item.status ?? "draft"),
    })),
    settings: {
      pilotProvinceCodes: Array.isArray(settings.pilotProvinceCodes) ? settings.pilotProvinceCodes.map(String) : [],
      provincialAwardsEnabled: Boolean(settings.provincialAwardsEnabled),
      provincialRankingsEnabled: Boolean(settings.provincialRankingsEnabled),
      revision: Number(settings.revision) || 1,
      seasonScoreEnabled: Boolean(settings.seasonScoreEnabled),
    },
    venueMappings: rows(root.venueMappings).map((item) => ({
      confidence: Number(item.confidence) || 0,
      effectiveFrom: String(item.effectiveFrom ?? ""),
      placeId: String(item.placeId ?? ""),
      provinceCode: String(item.provinceCode ?? "00"),
      revision: Number(item.revision) || 0,
      source: String(item.source ?? ""),
    })),
  };
}

function nextSeasonState(state: string) {
  if (state === "draft") return "open";
  if (state === "open") return "frozen";
  if (state === "frozen") return "closed";
  if (state === "closed") return "archived";
  return null;
}

export function RankingAdminClient({ canWrite, initialOverview }: { canWrite: boolean; initialOverview: unknown }) {
  const [overview, setOverview] = useState(() => normalizeOverview(initialOverview));
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("Operación validada desde Control Center");
  const [seasonLabel, setSeasonLabel] = useState("Piloto provincial Barcelona");
  const [seasonKey, setSeasonKey] = useState(`barcelona-${new Date().getUTCFullYear()}`);
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [placeId, setPlaceId] = useState("");
  const activeSeason = useMemo(() => overview.seasons.find((season) => ["open", "frozen"].includes(season.status)) ?? overview.seasons[0], [overview.seasons]);

  async function refresh() {
    const response = await fetch("/api/admin/rankings", { cache: "no-store" });
    const body = await response.json() as { data?: unknown; error?: string; message?: string };
    if (!response.ok) throw new Error(body.message ?? body.error ?? "No se pudo actualizar Rankings");
    setOverview(normalizeOverview(body.data));
  }

  async function run(action: string, payload: JsonRecord) {
    if (!canWrite || busy) return;
    setBusy(action);
    setMessage("");
    try {
      const response = await fetch("/api/admin/rankings", {
        body: JSON.stringify({ action, operationId: crypto.randomUUID(), reason, ...payload }),
        headers: { "Content-Type": "application/json", "x-pachangas-platform-admin": "1" },
        method: "POST",
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message ?? body.error ?? "Operación rechazada");
      await refresh();
      setMessage("Operación confirmada por el servidor.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operación rechazada");
      await refresh().catch(() => undefined);
    } finally {
      setBusy("");
    }
  }

  return <>
    <MetricGrid>
      <Metric label="Season Score" value={overview.settings.seasonScoreEnabled ? "ON" : "OFF"} tone={overview.settings.seasonScoreEnabled ? "good" : "warning"} hint="55 / 30 / 15 · recent_30" />
      <Metric label="Ranking provincial" value={overview.settings.provincialRankingsEnabled ? "ON" : "OFF"} tone={overview.settings.provincialRankingsEnabled ? "good" : "warning"} hint={overview.settings.pilotProvinceCodes.join(", ") || "Sin piloto"} />
      <Metric label="Cola" value={overview.queue.queued + overview.queue.processing} tone={overview.queue.failed || overview.queue.deadLetter ? "danger" : "neutral"} hint={`${overview.queue.failed} fallos · ${overview.queue.deadLetter} dead letter`} />
      <Metric label="Integridad" value={overview.integrity.pending} tone={overview.integrity.pending ? "warning" : "good"} hint="casos pendientes" />
      <Metric
        label="Salud"
        value={overview.health.status}
        tone={overview.health.status === "OK" ? "good" : overview.health.status === "CRITICAL" ? "danger" : "warning"}
        hint={overview.health.reasonCodes.slice(0, 2).join(" · ") || "Sin incidencias"}
      />
      <Metric label="Premios" value="OFF" tone="good" hint="0 grants en V1" />
      <Metric label="Fórmula" value={`V${overview.formula?.version ?? "-"}`} hint={overview.formula?.checksum.slice(0, 12) ?? "No disponible"} />
    </MetricGrid>

    {message ? <p className={styles.formMessage} role="status">{message}</p> : null}

    <Panel title="Temporadas y publicación">
      {overview.seasons.length ? <DataTable label="Temporadas productivas">
        <thead><tr><th>Temporada</th><th>Estado</th><th>Revisiones</th><th>Jugadores</th><th>Checksum</th><th>Acciones</th></tr></thead>
        <tbody>{overview.seasons.map((season) => {
          const nextState = nextSeasonState(season.status);
          return <tr key={season.id}>
            <td><strong>{season.label}</strong><small>{formatAdminDate(season.startsAt, false)} - {formatAdminDate(season.endsAt, false)}</small></td>
            <td><StatusBadge>{season.status}</StatusBadge>{season.lastErrorCode ? <small>{season.lastErrorCode}</small> : null}</td>
            <td>Season {season.revision}<small>Ranking {season.rankingRevision} · publicada {season.publishedRevision}</small></td>
            <td>{season.eligiblePlayers} elegibles<small>{season.notEligiblePlayers} fuera · {season.pendingIntegrityPlayers} pendientes</small></td>
            <td><code className={styles.identifier}>{season.candidateChecksum?.slice(0, 16) ?? "Sin candidato"}</code><small>{season.candidateCount} candidatos</small></td>
            <td><div className={styles.rankingActionRow}>
              {canWrite && nextState ? <button type="button" disabled={Boolean(busy)} onClick={() => void run("transition", { expectedRevision: season.revision, nextStatus: nextState, seasonId: season.id })}>{nextState}</button> : null}
              {canWrite && ["open", "frozen"].includes(season.status) ? <button type="button" disabled={Boolean(busy)} onClick={() => void run("rebuild", { expectedRevision: season.revision, seasonId: season.id })}>Rebuild</button> : null}
              {canWrite && season.rebuildId && season.rebuildState === "candidate_ready" && season.candidateChecksum ? <button type="button" disabled={Boolean(busy)} onClick={() => void run("publish", { candidateChecksum: season.candidateChecksum, expectedRevision: season.revision, rebuildId: season.rebuildId })}>Publicar</button> : null}
            </div></td>
          </tr>;
        })}</tbody>
      </DataTable> : <EmptyState>No hay temporadas canónicas.</EmptyState>}
    </Panel>

    {canWrite ? <div className={styles.rankingAdminGrid}>
      <Panel title="Crear temporada">
        <form className={styles.rankingForm} onSubmit={(event) => {
          event.preventDefault();
          void run("createSeason", { endsAt, provinceCodes: ["08"], seasonKey, seasonLabel, startsAt });
        }}>
          <label className={styles.formField}>Nombre<input value={seasonLabel} onChange={(event) => setSeasonLabel(event.target.value)} required /></label>
          <label className={styles.formField}>Clave<input value={seasonKey} onChange={(event) => setSeasonKey(event.target.value)} pattern="[a-z0-9_-]{3,80}" required /></label>
          <div className={styles.rankingFormColumns}>
            <label className={styles.formField}>Inicio<input type="datetime-local" value={startsAt} onChange={(event) => setStartsAt(event.target.value)} required /></label>
            <label className={styles.formField}>Fin<input type="datetime-local" value={endsAt} onChange={(event) => setEndsAt(event.target.value)} required /></label>
          </div>
          <button className={styles.primaryButton} disabled={Boolean(busy)} type="submit">Crear borrador</button>
        </form>
      </Panel>
      <Panel title="Territorio y cola">
        <form className={styles.rankingForm} onSubmit={(event) => {
          event.preventDefault();
          const current = overview.venueMappings.find((mapping) => mapping.placeId === placeId);
          void run("mapVenue", { expectedMappingRevision: current?.revision ?? 0, placeId, provinceCode: "08" });
        }}>
          <label className={styles.formField}>Google Place ID<input value={placeId} onChange={(event) => setPlaceId(event.target.value)} required /></label>
          <button className={styles.secondaryButton} disabled={Boolean(busy)} type="submit">Verificar como Barcelona</button>
          <button className={styles.primaryButton} disabled={Boolean(busy)} type="button" onClick={() => void run("processQueue", { expectedSettingsRevision: overview.settings.revision, maximumOperations: 25 })}>Procesar cola</button>
        </form>
      </Panel>
    </div> : null}

    {canWrite ? <label className={`${styles.formField} ${styles.rankingReason}`}>Motivo auditable<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label> : null}

    <Panel title="Cola de refresh">
      {overview.queueItems.length ? <DataTable label="Cola de Ranking">
        <thead><tr><th>Temporada</th><th>Ámbito</th><th>Estado</th><th>Intentos</th><th>Origen</th></tr></thead>
        <tbody>{overview.queueItems.map((item) => <tr key={item.id}><td>{item.seasonLabel}<small>{item.reason}</small></td><td>{item.scope}</td><td><StatusBadge>{item.state}</StatusBadge>{item.errorCode ? <small>{item.errorCode}</small> : null}</td><td>{item.attempts}<small>{formatAdminDate(item.availableAt)}</small></td><td>{item.sourceType}</td></tr>)}</tbody>
      </DataTable> : <EmptyState>No hay refresh pendientes ni fallidos.</EmptyState>}
    </Panel>

    <Panel title="Revisión de integridad deportiva">
      {overview.integrityReviews.length ? <DataTable label="Casos pendientes de integridad">
        <thead><tr><th>Jugador</th><th>Riesgo</th><th>Evidencia</th><th>Motivos internos</th><th>Decisión</th></tr></thead>
        <tbody>{overview.integrityReviews.map((review) => <tr key={review.id}>
          <td>{review.playerName}<small>{review.seasonLabel} · {review.provinceCode} · {review.reference.slice(0, 8)}</small></td>
          <td><StatusBadge tone={review.riskClassification === "high_risk" ? "danger" : "warning"}>{review.riskClassification}</StatusBadge><small>{review.riskScore.toFixed(1)} / 100</small></td>
          <td>{Number(review.evidenceSummary.validChallenges) || 0} retos<small>{Number(review.evidenceSummary.logicalOpponents) || 0} rivales · red {Number(review.evidenceSummary.networkDiversity ?? 0).toFixed(2)}</small></td>
          <td>{review.reasonCodes.join(" · ") || "Sin códigos"}<small>{formatAdminDate(review.createdAt)}</small></td>
          <td><div className={styles.rankingActionRow}>{canWrite ? <>
            <button type="button" disabled={Boolean(busy)} onClick={() => void run("resolveIntegrity", { expectedRevision: review.revision, resolution: "evidence_valid", reviewId: review.id })}>Confirmar</button>
            <button type="button" disabled={Boolean(busy)} onClick={() => void run("resolveIntegrity", { expectedRevision: review.revision, resolution: "evidence_excluded", reviewId: review.id })}>Excluir</button>
          </> : <span>Solo lectura</span>}</div></td>
        </tr>)}</tbody>
      </DataTable> : <EmptyState>No hay casos pendientes.</EmptyState>}
    </Panel>

    <Panel title="Invariantes de esta release">
      <div className={styles.rankingInvariantRow}>
        <StatusBadge tone={overview.invariants.ratingV2ReadOnly ? "good" : "danger"}>Rating V2 solo lectura</StatusBadge>
        <StatusBadge tone={!overview.invariants.conductAffectsScore ? "good" : "danger"}>Conducta no puntúa</StatusBadge>
        <StatusBadge tone={!overview.invariants.rewardsAffectScore ? "good" : "danger"}>Rewards no puntúan</StatusBadge>
        <StatusBadge tone={!overview.invariants.awardsEnabled ? "good" : "danger"}>Awards OFF</StatusBadge>
        {activeSeason ? <span>Activa: {activeSeason.label}</span> : null}
      </div>
    </Panel>
  </>;
}
