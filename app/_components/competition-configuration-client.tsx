"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import {
  competitionConfigurationCacheVersion,
  competitionConfigurationRealtimeTable,
  configurationArray,
  configurationBoolean,
  configurationHealthTone,
  configurationNumber,
  configurationRecord,
  configurationText,
  type CompetitionConfigurationAction,
  type CompetitionConfigurationJson,
} from "../competition-configuration-contract";
import { leaguePrivateBetaPresets, leaguePrivateBetaSteps } from "../league-private-beta-contract";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import { CompetitionConfigurationFields, competitionConfigurationStepPayload, type CompetitionAuthoringMode } from "./competition-configuration-fields";
import { CompetitionPublicationControl } from "./competition-publication-control";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import { GamePageHeader, MetricTile, ProductFeedback, SectionHeader, StatusChip } from "./official-ui-v2-primitives";
import styles from "./competition-configuration-client.module.css";

const cachePrefix = "pachangas-competition-configuration-read-v1";

function cacheKey(userId: string, competitionId: string) { return `${cachePrefix}:${userId}:${competitionId}`; }

function readCache(userId: string, competitionId: string) {
  try {
    const envelope = configurationRecord(JSON.parse(window.localStorage.getItem(cacheKey(userId, competitionId)) ?? "null"));
    if (configurationNumber(envelope.version) !== competitionConfigurationCacheVersion) return null;
    if (Date.now() > configurationNumber(envelope.expiresAt)) return null;
    return configurationRecord(envelope.data);
  } catch { return null; }
}

function writeCache(userId: string, competitionId: string, data: CompetitionConfigurationJson) {
  try {
    window.localStorage.setItem(cacheKey(userId, competitionId), JSON.stringify({
      data,
      expiresAt: Date.now() + 5 * 60 * 1000,
      storedAt: new Date().toISOString(),
      version: competitionConfigurationCacheVersion,
    }));
  } catch {
    // Disposable read cache only. PostgreSQL remains authoritative.
  }
}

function Status({ value }: { value: unknown }) {
  return <StatusChip tone={configurationHealthTone(value)}>{configurationText(value).replaceAll("_", " ") || "sin estado"}</StatusChip>;
}

function modality(value: unknown) {
  const labels: Record<string, string> = { FUTBOL_5: "Fútbol 5", FUTBOL_7: "Fútbol 7", FUTBOL_11: "Fútbol 11", FUTSAL: "Fútbol sala" };
  return labels[configurationText(value)] ?? configurationText(value) ?? "Sin modalidad";
}

function PolicySummary({ summary }: { summary: CompetitionConfigurationJson }) {
  const format = configurationRecord(summary.format);
  const matches = configurationRecord(summary.matches);
  const scoring = configurationRecord(summary.scoring);
  const discipline = configurationRecord(summary.discipline);
  const referees = configurationRecord(summary.referees);
  const cards = configurationArray(discipline.cards);
  const tieBreaks = Array.isArray(summary.tieBreaks) ? summary.tieBreaks.map(String) : [];
  return <div className={styles.summaryGrid}>
    <div><span>Formato</span><strong>{modality(format.modality)}</strong><small>Hasta {configurationNumber(format.teamsMaximum)} equipos</small></div>
    <div><span>Partidos</span><strong>{configurationNumber(matches.matchDurationMinutes)} min</strong><small>{configurationNumber(matches.minimumRestMinutes)} min de descanso</small></div>
    <div><span>Puntuación</span><strong>{configurationNumber(scoring.win)} / {configurationNumber(scoring.draw)} / {configurationNumber(scoring.loss)}</strong><small>Victoria · empate · derrota</small></div>
    <div><span>Desempates</span><strong>{tieBreaks.length}</strong><small>{tieBreaks.slice(0, 3).map((item) => item.replaceAll("_", " ")).join(" · ")}</small></div>
    <div><span>Disciplina</span><strong>{configurationBoolean(discipline.enabled) ? `${cards.length} tarjetas` : "Desactivada"}</strong><small>Catálogo R5 de esta revisión</small></div>
    <div><span>Árbitro</span><strong>{configurationText(referees.usage) || "NONE"}</strong><small>MAIN_REFEREE</small></div>
  </div>;
}

function Health({ health }: { health: CompetitionConfigurationJson }) {
  const errors = configurationArray(health.errors);
  const warnings = configurationArray(health.warnings);
  const off = Array.isArray(health.globallyDisabled) ? health.globallyDisabled.map(String) : [];
  return <section className={styles.health}>
    <header><div><span>Health</span><h3>Configuración {configurationText(health.status) || "pendiente"}</h3></div><Status value={health.status} /></header>
    {errors.map((item) => <p className={styles.error} key={configurationText(item.code)}><strong>{configurationText(item.code)}</strong>{configurationText(item.message)}</p>)}
    {warnings.map((item) => <p className={styles.warning} key={configurationText(item.code)}>{configurationText(item.message)}</p>)}
    {off.length ? <div className={styles.offline}><strong>Funciones apagadas</strong>{off.map((item) => <span key={item}>{item.replaceAll("_", " ")}</span>)}</div> : null}
  </section>;
}

function Impact({ impact }: { impact: CompetitionConfigurationJson }) {
  const differences = configurationRecord(impact.differences);
  const changed = Object.entries(differences).filter(([, value]) => configurationBoolean(configurationRecord(value).changed));
  return <section className={styles.impact}>
    <SectionHeader eyebrow="Antes de publicar" title="Impacto y diferencias" />
    <div className={styles.impactMetrics}>
      <MetricTile label="Partidos futuros" value={configurationNumber(impact.futureMatches)} />
      <MetricTile label="Jugadores" value={configurationNumber(impact.players)} />
      <MetricTile label="Contadores" value={configurationNumber(impact.disciplinaryCounters)} />
      <MetricTile label="Sanciones" value={configurationNumber(impact.activeSanctions)} />
      <MetricTile label="Árbitros" value={configurationNumber(impact.refereeAssignments)} />
      <MetricTile label="Resultados" value={configurationNumber(impact.sportingResults)} />
    </div>
    <div className={styles.changedSections}>{changed.length ? changed.map(([key]) => <span key={key}>{key}</span>) : <span>Sin diferencias materiales</span>}</div>
    <p>{configurationBoolean(impact.requiresExplicitRebind) ? "La revisión queda futura y exige aplicación administrativa explícita; no reescribe historia." : "La edición está en draft y puede adoptar esta revisión como autoridad actual."}</p>
  </section>;
}

export function CompetitionConfigurationClient({ competitionId }: { competitionId: string }) {
  const [data, setData] = useState<CompetitionConfigurationJson | null>(null);
  const [activeStep, setActiveStep] = useState(1);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(true);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [createMode, setCreateMode] = useState<CompetitionAuthoringMode>("SIMPLE");
  const [createPreset, setCreatePreset] = useState("LEAGUE_F7_STANDARD");
  const [publishConfirmed, setPublishConfirmed] = useState(false);
  const pending = useRef<{ id: string; key: string } | null>(null);
  const timer = useRef<number | null>(null);

  const load = useCallback(async (token: string, actorId: string, source: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch(`/api/competitions/configuration/${competitionId}`, { cache: "no-store", headers: { Authorization: `Bearer ${token}` } });
      const body = configurationRecord(await response.json());
      if (!response.ok) throw new Error(configurationText(body.message) || "No se pudo cargar la configuración.");
      setData(body);
      setCached(false);
      writeCache(actorId, competitionId, body);
      const draft = configurationRecord(body.draft);
      if (configurationText(draft.id)) setActiveStep(Math.min(12, Math.max(1, configurationNumber(draft.currentStep))));
      if (source === "realtime") setMessage("Configuración actualizada desde el servidor.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo cargar la configuración.");
    } finally { setLoading(false); }
  }, [competitionId]);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const sessionResult = await supabase?.auth.getSession();
      if (!active) return;
      const session = sessionResult?.data.session;
      if (!session) { setLoading(false); setMessage("Inicia sesión para abrir esta configuración."); return; }
      const token = session.access_token; const actorId = session.user.id;
      setAccessToken(token); setUserId(actorId);
      const local = readCache(actorId, competitionId);
      if (local) { setData(local); setCached(true); setLoading(false); }
      await load(token, actorId, "initial");
      if (!supabase) return;
      const reconcile = () => void load(token, actorId, "realtime");
      window.addEventListener("online", reconcile);
      channel = supabase.channel(`competition-configuration:${competitionId}:${actorId}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: competitionConfigurationRealtimeTable }, (payload) => {
          const row = configurationRecord(payload.new);
          if (configurationText(row.competition_id) !== competitionId) return;
          if (timer.current) window.clearTimeout(timer.current);
          timer.current = window.setTimeout(reconcile, 120);
        })
        .subscribe((state) => { if (state === "SUBSCRIBED") reconcile(); });
      return () => window.removeEventListener("online", reconcile);
    };
    let cleanup: (() => void) | undefined;
    void start().then((value) => { if (!active) value?.(); else cleanup = value; });
    return () => { active = false; cleanup?.(); if (timer.current) window.clearTimeout(timer.current); if (channel && supabase) void supabase.removeChannel(channel); };
  }, [competitionId, load]);

  async function command(action: CompetitionConfigurationAction, aggregateId: string, expectedRevision: number, payload: CompetitionConfigurationJson) {
    if (!accessToken || !userId) return;
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true); setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:competition-configuration-command", "/api/competitions/configuration/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = configurationRecord(await response.json());
      if (!response.ok) throw new Error(configurationText(body.message) || "Operación no confirmada.");
      pending.current = null; setMessage("Cambio confirmado por el servidor."); setPublishConfirmed(false);
      await load(accessToken, userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Se ha recuperado el estado oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await load(accessToken, userId, "mutation");
    } finally { setBusy(false); }
  }

  const competition = configurationRecord(data?.competition);
  const edition = configurationRecord(data?.edition);
  const capabilities = configurationRecord(data?.capabilities);
  const currentRevision = configurationRecord(data?.currentRuleRevision);
  const draft = configurationRecord(data?.draft);
  const currentSummary = configurationRecord(currentRevision.summary);
  const steps = configurationRecord(draft.steps);
  const currentStepData = configurationRecord(steps[String(activeStep)]);
  const health = configurationRecord(draft.health);
  const impact = configurationRecord(draft.impact);
  const mode = (configurationText(draft.authoringMode) === "ADVANCED" ? "ADVANCED" : "SIMPLE") as CompetitionAuthoringMode;
  const revisions = configurationArray(data?.revisions);
  const canEdit = configurationBoolean(capabilities.edit);

  function saveSection(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!configurationText(draft.id)) return;
    void command("draft.section.save", configurationText(draft.id), configurationNumber(draft.revision), {
      data: competitionConfigurationStepPayload(activeStep, new FormData(event.currentTarget), currentStepData),
      reason: `Configuración paso ${activeStep}`,
      step: activeStep,
    });
  }

  return <OfficialProductShellV2 active="competir" perspective="league-organizer" context={{ detail: configurationText(edition.seasonLabel), eyebrow: "Competition Configuration", status: configurationText(data?.freezePoint) || "DRAFT", title: configurationText(competition.name) || "Configuración" }}>
    <main className={styles.page}>
      <GamePageHeader eyebrow="Autoridad canónica" title={configurationText(competition.name) || "Configuración de competición"} summary="Edita un borrador legible; PostgreSQL valida y publica una RuleRevision nueva sin reescribir el pasado." />
      {cached ? <ProductFeedback tone="warning">Mostrando caché de lectura mientras se confirma la revisión actual.</ProductFeedback> : null}
      {message ? <ProductFeedback tone={/confirmado|actualizada/i.test(message) ? "success" : "info"}>{message}</ProductFeedback> : null}
      {loading ? <section className={styles.state}><strong>Cargando configuración...</strong></section> : null}
      {!loading && !accessToken ? <section className={styles.state}><strong>Sesión necesaria</strong><Link href="/">Volver a Inicio</Link></section> : null}
      {data ? <>
        <section className={styles.heroBand}>
          <div><span>RuleRevision v{configurationNumber(currentRevision.version)}</span><h2>{configurationText(edition.name)}</h2><p>Freeze point: {configurationText(data.freezePoint)} · Hash {configurationText(currentRevision.checksum).slice(0, 12)}</p></div>
          <div className={styles.metrics}><MetricTile label="Revisiones" value={revisions.length} /><MetricTile label="Edición" value={configurationText(edition.status)} /><MetricTile label="Rol" value={configurationText(competition.actorRole)} /></div>
        </section>

        {!configurationText(draft.id) ? <>
          <section><SectionHeader eyebrow="Reglamento vigente" title="Resumen canónico" /><PolicySummary summary={currentSummary} /></section>
          {canEdit ? <section className={styles.createPanel}><SectionHeader eyebrow="Nueva revisión" title="Abrir borrador de configuración" /><div className={styles.createOptions}><label>Modo<select value={createMode} onChange={(event) => setCreateMode(event.target.value as CompetitionAuthoringMode)}><option value="SIMPLE">Sencillo</option><option value="ADVANCED">Avanzado</option></select></label><label>Preset<select value={createPreset} onChange={(event) => setCreatePreset(event.target.value)}>{leaguePrivateBetaPresets.map((preset) => <option key={preset.key} value={preset.key}>{preset.label}</option>)}</select></label></div><div className={styles.createActions}><button type="button" disabled={busy} onClick={() => void command("draft.clone", competitionId, configurationNumber(competition.revision), { authoringMode: createMode, editionId: configurationText(edition.id), reason: "Clonar RuleRevision vigente", sourceRuleRevisionId: configurationText(currentRevision.id) })}>Clonar revisión vigente</button><button className={styles.primary} type="button" disabled={busy} onClick={() => void command("draft.create", competitionId, configurationNumber(competition.revision), { authoringMode: createMode, editionId: configurationText(edition.id), presetKey: createPreset, reason: "Nueva configuración desde preset", sourceRuleRevisionId: configurationText(currentRevision.id) })}>Empezar desde preset</button></div></section> : null}
          <section><SectionHeader eyebrow="Historial" title="Revisiones congeladas" /><div className={styles.revisionRail}>{revisions.map((revision) => <article key={configurationText(revision.id)}><div><Status value={revision.status} /><span>v{configurationNumber(revision.version)}</span></div><strong>{new Date(configurationText(revision.effectiveFrom)).toLocaleDateString("es-ES")}</strong><small>{configurationText(revision.checksum).slice(0, 16)}</small></article>)}</div></section>
        </> : <section className={styles.editor}>
          <header className={styles.editorHeader}><div><span>Borrador v{configurationNumber(draft.revision)} · {mode === "ADVANCED" ? "Avanzado" : "Sencillo"}</span><h2>{leaguePrivateBetaSteps[activeStep - 1]?.label}</h2></div><Status value={draft.status} /></header>
          <div className={styles.tools}><div role="group" aria-label="Modo de autoría"><button type="button" aria-pressed={mode === "SIMPLE"} disabled={busy} onClick={() => void command("draft.mode.set", configurationText(draft.id), configurationNumber(draft.revision), { mode: "SIMPLE", reason: "Modo sencillo" })}>Sencillo</button><button type="button" aria-pressed={mode === "ADVANCED"} disabled={busy} onClick={() => void command("draft.mode.set", configurationText(draft.id), configurationNumber(draft.revision), { mode: "ADVANCED", reason: "Modo avanzado" })}>Avanzado</button></div><label>Preset<select value={configurationText(draft.presetKey)} disabled={busy} onChange={(event) => void command("draft.preset.apply", configurationText(draft.id), configurationNumber(draft.revision), { presetKey: event.target.value, reason: "Preset copiado al borrador" })}>{leaguePrivateBetaPresets.map((preset) => <option key={preset.key} value={preset.key}>{preset.label}</option>)}</select></label></div>
          <div className={styles.editorBody}>
            <nav className={styles.stepRail} aria-label="Secciones del reglamento">{leaguePrivateBetaSteps.map((item) => <button type="button" key={item.id} aria-current={activeStep === item.id ? "step" : undefined} onClick={() => setActiveStep(item.id)}><b>{item.id}</b><span>{item.label}</span></button>)}</nav>
            <form className={styles.form} key={`${configurationText(draft.id)}:${activeStep}:${configurationNumber(draft.revision)}`} onSubmit={saveSection}><CompetitionConfigurationFields data={currentStepData} mode={mode} step={activeStep} /><footer><button type="button" disabled={busy} onClick={() => void command("draft.cancel", configurationText(draft.id), configurationNumber(draft.revision), { reason: "Borrador cancelado" })}>Cancelar</button><button className={styles.primary} type="submit" disabled={busy || configurationText(draft.status) === "validated"}>Guardar sección</button></footer></form>
          </div>
          <Health health={health} />
          <section><SectionHeader eyebrow="Reglamento propuesto" title="Resumen legible" /><PolicySummary summary={configurationRecord(draft.summary)} /></section>
          <Impact impact={impact} />
          <div className={styles.releaseBar}>{configurationText(draft.status) === "validated" ? <><label><input type="checkbox" checked={publishConfirmed} onChange={(event) => setPublishConfirmed(event.target.checked)} />He revisado el resumen y el impacto.</label><button className={styles.publish} type="button" disabled={busy || !publishConfirmed} onClick={() => void command("draft.publish", configurationText(draft.id), configurationNumber(draft.revision), { confirmImpact: true, confirmRuleSummary: true, reason: "Nueva RuleRevision confirmada" })}>Publicar RuleRevision</button></> : <button className={styles.validate} type="button" disabled={busy || !configurationBoolean(health.complete)} onClick={() => void command("draft.validate", configurationText(draft.id), configurationNumber(draft.revision), { effectiveFrom: new Date(Date.now() + 60_000).toISOString(), effectiveScope: "FUTURE_ONLY", reason: "Validación previa a publicación" })}>Validar configuración</button>}</div>
        </section>}
        {canEdit ? <CompetitionPublicationControl competitionId={competitionId} competitionName={configurationText(competition.name)} /> : null}
      </> : null}
    </main>
  </OfficialProductShellV2>;
}
