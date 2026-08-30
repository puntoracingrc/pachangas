"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  leagueBetaArray,
  leagueBetaBoolean,
  leagueBetaNextActionLabel,
  leagueBetaNumber,
  leagueBetaRecord,
  leagueBetaStatusTone,
  leagueBetaText,
  leaguePrivateBetaCacheVersion,
  leaguePrivateBetaPresets,
  leaguePrivateBetaRealtimeTable,
  leaguePrivateBetaSteps,
  type LeaguePrivateBetaAction,
  type LeaguePrivateBetaJson,
} from "../league-private-beta-contract";
import {
  CompetitionConfigurationFields,
  competitionConfigurationStepPayload,
  type CompetitionAuthoringMode,
} from "./competition-configuration-fields";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./league-private-beta-client.module.css";

const dashboardCacheKey = "pachangas-league-private-beta-read-v1";

function localDate(monthOffset: number) {
  const date = new Date();
  date.setUTCMonth(date.getUTCMonth() + monthOffset);
  return date.toISOString().slice(0, 10);
}

function localTimestamp(monthOffset: number) {
  return `${localDate(monthOffset)}T23:59`;
}

function readCache(userId: string) {
  try {
    const envelope = leagueBetaRecord(JSON.parse(
      window.localStorage.getItem(`${dashboardCacheKey}:${userId}`) ?? "null",
    ));
    return leagueBetaNumber(envelope.version) === leaguePrivateBetaCacheVersion
      ? leagueBetaRecord(envelope.data)
      : null;
  } catch {
    return null;
  }
}

function writeCache(userId: string, data: LeaguePrivateBetaJson) {
  try {
    window.localStorage.setItem(`${dashboardCacheKey}:${userId}`, JSON.stringify({
      data,
      storedAt: new Date().toISOString(),
      version: leaguePrivateBetaCacheVersion,
    }));
  } catch {
    // This is a disposable read cache, never product authority.
  }
}

function status(value: unknown) {
  const label = leagueBetaText(value).replaceAll("_", " ") || "sin estado";
  return <StatusChip tone={leagueBetaStatusTone(value)}>{label}</StatusChip>;
}

function formText(form: FormData, key: string) {
  return String(form.get(key) ?? "").trim();
}

function formNumber(form: FormData, key: string) {
  return Number(form.get(key));
}

function formBoolean(form: FormData, key: string) {
  return form.get(key) === "on";
}

function stepPayload(step: number, form: FormData, current: LeaguePrivateBetaJson): LeaguePrivateBetaJson {
  if (step === 1) return {
    description: formText(form, "description"),
    generalArea: formText(form, "generalArea"),
    imageUrl: formText(form, "imageUrl"),
    name: formText(form, "name"),
    slug: formText(form, "slug"),
  };
  if (step === 2) return { modality: formText(form, "modality") };
  if (step === 3) return {
    editionName: formText(form, "editionName"),
    endsAt: formText(form, "endsAt"),
    seasonLabel: formText(form, "seasonLabel"),
    startsAt: formText(form, "startsAt"),
    timezone: "Europe/Madrid",
  };
  if (step === 4) return {
    legs: formNumber(form, "legs"),
    registrationClosesAt: new Date(formText(form, "registrationClosesAt")).toISOString(),
    registrationMode: "INVITE_ONLY",
    teamCap: formNumber(form, "teamCap"),
  };
  if (step === 5) return {
    closeRequiresApprovedRosters: formBoolean(form, "closeRequiresApprovedRosters"),
    credentialRequired: formBoolean(form, "credentialRequired"),
    jerseyRequired: formBoolean(form, "jerseyRequired"),
    maximumRosterSize: formNumber(form, "maximumRosterSize"),
    minimumRosterSize: formNumber(form, "minimumRosterSize"),
  };
  if (step === 6) return {
    autoOfficialAfterConfirmation: formBoolean(form, "autoOfficialAfterConfirmation"),
    matchDurationMinutes: formNumber(form, "matchDurationMinutes"),
    pointsForDraw: formNumber(form, "pointsForDraw"),
    pointsForLoss: formNumber(form, "pointsForLoss"),
    pointsForWin: formNumber(form, "pointsForWin"),
    requiredBufferMinutes: formNumber(form, "requiredBufferMinutes"),
    responseDeadlineHours: formNumber(form, "responseDeadlineHours"),
  };
  if (step === 7) return {
    allowTbd: formBoolean(form, "allowTbd"),
    minimumRestMinutes: formNumber(form, "minimumRestMinutes"),
    useDivision: formBoolean(form, "useDivision"),
    venueRequired: formBoolean(form, "venueRequired"),
    weeklyPattern: [{ dayOfWeek: formNumber(form, "dayOfWeek"), startTime: formText(form, "startTime") }],
  };
  if (step === 8) return {
    allowSharedPositions: formBoolean(form, "allowSharedPositions"),
    allowUnknownScorer: false,
    scorerDetailPolicy: formText(form, "scorerDetailPolicy"),
    tieBreakCriteria: form.getAll("tieBreakCriteria").map(String),
  };
  if (step === 9) return {
    gracePeriodMinutes: formNumber(form, "gracePeriodMinutes"),
    maximumMatchDurationMinutes: 180,
    minimumRestHours: formNumber(form, "minimumRestHours"),
    noShowLoserScore: formNumber(form, "noShowLoserScore"),
    noShowOutcome: "NO_SHOW",
    noShowWinnerScore: formNumber(form, "noShowWinnerScore"),
    postponementDeadlinePolicy: formText(form, "postponementDeadlinePolicy"),
    postponementResponseDeadlineHours: formNumber(form, "postponementResponseDeadlineHours"),
  };
  return competitionConfigurationStepPayload(step, form, current);
}

function value(step: LeaguePrivateBetaJson, key: string, fallback: string | number | boolean) {
  return step[key] ?? fallback;
}

function WizardFields({ data, mode, step }: { data: LeaguePrivateBetaJson; mode: CompetitionAuthoringMode; step: number }) {
  if (step === 1) return <>
    <label>Nombre<input name="name" required maxLength={120} defaultValue={String(value(data, "name", "Liga privada"))} /></label>
    <label>Slug privado<input name="slug" required maxLength={80} pattern="[a-z0-9]+(?:-[a-z0-9]+)*" defaultValue={String(value(data, "slug", "liga-privada"))} /></label>
    <label className={styles.wide}>Descripción<textarea name="description" rows={3} maxLength={2400} defaultValue={String(value(data, "description", ""))} /></label>
    <label>Zona general<input name="generalArea" maxLength={160} defaultValue={String(value(data, "generalArea", ""))} /></label>
    <label>Imagen HTTPS opcional<input name="imageUrl" type="url" defaultValue={String(value(data, "imageUrl", ""))} /></label>
  </>;
  if (step === 2) return <label className={styles.wide}>Modalidad<select name="modality" defaultValue={String(value(data, "modality", "FUTBOL_7"))}><option value="FUTBOL_5">Fútbol 5</option><option value="FUTBOL_7">Fútbol 7</option><option value="FUTBOL_11">Fútbol 11</option><option value="FUTSAL">Fútbol sala</option></select></label>;
  if (step === 3) return <>
    <label>Nombre de edición<input name="editionName" required defaultValue={String(value(data, "editionName", "Temporada inicial"))} /></label>
    <label>Etiqueta de temporada<input name="seasonLabel" required defaultValue={String(value(data, "seasonLabel", new Date().getFullYear() + 1))} /></label>
    <label>Inicio<input name="startsAt" type="date" required defaultValue={String(value(data, "startsAt", localDate(2)))} /></label>
    <label>Fin<input name="endsAt" type="date" required defaultValue={String(value(data, "endsAt", localDate(10)))} /></label>
  </>;
  if (step === 4) return <>
    <label>Máximo de equipos<input name="teamCap" type="number" min={4} max={20} required defaultValue={Number(value(data, "teamCap", 6))} /></label>
    <label>Vueltas<select name="legs" defaultValue={Number(value(data, "legs", 1))}><option value="1">Una vuelta</option><option value="2">Ida y vuelta</option></select></label>
    <label className={styles.wide}>Cierre de inscripción<input name="registrationClosesAt" type="datetime-local" required defaultValue={String(value(data, "registrationClosesAt", localTimestamp(1))).slice(0, 16)} /></label>
    <p className={styles.locked}>Registro privado por invitación. No se publicará un formulario abierto.</p>
  </>;
  if (step === 5) return <>
    <label>Mínimo de plantilla<input name="minimumRosterSize" type="number" min={1} max={50} required defaultValue={Number(value(data, "minimumRosterSize", 7))} /></label>
    <label>Máximo de plantilla<input name="maximumRosterSize" type="number" min={1} max={50} required defaultValue={Number(value(data, "maximumRosterSize", 18))} /></label>
    <label className={styles.check}><input name="credentialRequired" type="checkbox" defaultChecked={Boolean(value(data, "credentialRequired", true))} />Credencial obligatoria</label>
    <label className={styles.check}><input name="jerseyRequired" type="checkbox" defaultChecked={Boolean(value(data, "jerseyRequired", true))} />Dorsal obligatorio</label>
    <label className={styles.check}><input name="closeRequiresApprovedRosters" type="checkbox" defaultChecked={Boolean(value(data, "closeRequiresApprovedRosters", true))} />Cerrar solo con plantillas aprobadas</label>
  </>;
  if (step === 6) return <>
    <label>Duración (min)<input name="matchDurationMinutes" type="number" min={20} max={180} required defaultValue={Number(value(data, "matchDurationMinutes", 70))} /></label>
    <label>Buffer (min)<input name="requiredBufferMinutes" type="number" min={0} max={120} required defaultValue={Number(value(data, "requiredBufferMinutes", 10))} /></label>
    <label>Victoria<input name="pointsForWin" type="number" min={0} max={10} required defaultValue={Number(value(data, "pointsForWin", 3))} /></label>
    <label>Empate<input name="pointsForDraw" type="number" min={0} max={10} required defaultValue={Number(value(data, "pointsForDraw", 1))} /></label>
    <label>Derrota<input name="pointsForLoss" type="number" min={0} max={10} required defaultValue={Number(value(data, "pointsForLoss", 0))} /></label>
    <label>Confirmación (h)<input name="responseDeadlineHours" type="number" min={1} max={720} required defaultValue={Number(value(data, "responseDeadlineHours", 48))} /></label>
    <label className={styles.check}><input name="autoOfficialAfterConfirmation" type="checkbox" defaultChecked={Boolean(value(data, "autoOfficialAfterConfirmation", true))} />Oficial tras confirmación bilateral</label>
  </>;
  if (step === 7) return <>
    <label>Día habitual<select name="dayOfWeek" defaultValue={6}><option value="1">Lunes</option><option value="2">Martes</option><option value="3">Miércoles</option><option value="4">Jueves</option><option value="5">Viernes</option><option value="6">Sábado</option><option value="7">Domingo</option></select></label>
    <label>Hora habitual<input name="startTime" type="time" required defaultValue="18:00" /></label>
    <label>Descanso mínimo (min)<input name="minimumRestMinutes" type="number" min={0} defaultValue={Number(value(data, "minimumRestMinutes", 1440))} /></label>
    <label className={styles.check}><input name="venueRequired" type="checkbox" defaultChecked={Boolean(value(data, "venueRequired", false))} />Sede obligatoria</label>
    <label className={styles.check}><input name="allowTbd" type="checkbox" defaultChecked={Boolean(value(data, "allowTbd", true))} />Permitir sede por confirmar</label>
    <label className={styles.check}><input name="useDivision" type="checkbox" defaultChecked={Boolean(value(data, "useDivision", true))} />Crear división única</label>
  </>;
  if (step === 8) return <>
    <fieldset className={styles.wide}><legend>Desempates, en orden</legend>{["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR", "WINS", "PERSISTED_DRAW_LOT"].map((criterion) => <label className={styles.check} key={criterion}><input name="tieBreakCriteria" type="checkbox" value={criterion} defaultChecked />{criterion.replaceAll("_", " ")}</label>)}</fieldset>
    <label>Detalle de goleadores<select name="scorerDetailPolicy" defaultValue={String(value(data, "scorerDetailPolicy", "OPTIONAL"))}><option value="OPTIONAL">Opcional</option><option value="REQUIRED">Obligatorio</option><option value="DISABLED">Desactivado</option></select></label>
    <label className={styles.check}><input name="allowSharedPositions" type="checkbox" defaultChecked={Boolean(value(data, "allowSharedPositions", true))} />Permitir posiciones compartidas</label>
  </>;
  if (step === 9) return <>
    <label>Respuesta a aplazamiento (h)<input name="postponementResponseDeadlineHours" type="number" min={1} max={720} defaultValue={Number(value(data, "postponementResponseDeadlineHours", 48))} /></label>
    <label>Al vencer<select name="postponementDeadlinePolicy" defaultValue={String(value(data, "postponementDeadlinePolicy", "ESCALATE_TO_ORGANIZER"))}><option value="ESCALATE_TO_ORGANIZER">Escalar al organizador</option><option value="AUTO_DENY">Rechazar</option><option value="EXPIRE">Expirar</option></select></label>
    <label>Margen de llegada (min)<input name="gracePeriodMinutes" type="number" min={0} max={180} defaultValue={Number(value(data, "gracePeriodMinutes", 15))} /></label>
    <label>Descanso tras cambio (h)<input name="minimumRestHours" type="number" min={0} defaultValue={Number(value(data, "minimumRestHours", 24))} /></label>
    <label>Marcador ganador no-show<input name="noShowWinnerScore" type="number" min={0} max={99} defaultValue={Number(value(data, "noShowWinnerScore", 3))} /></label>
    <label>Marcador perdedor no-show<input name="noShowLoserScore" type="number" min={0} max={99} defaultValue={Number(value(data, "noShowLoserScore", 0))} /></label>
  </>;
  return <CompetitionConfigurationFields data={data} mode={mode} step={step} />;
}

export function LeaguePrivateBetaClient() {
  const [data, setData] = useState<LeaguePrivateBetaJson | null>(null);
  const [wizard, setWizard] = useState<LeaguePrivateBetaJson | null>(null);
  const [activeStep, setActiveStep] = useState(1);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(true);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [createMode, setCreateMode] = useState<CompetitionAuthoringMode>("SIMPLE");
  const [createPreset, setCreatePreset] = useState("LEAGUE_F7_STANDARD");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);
  const wizardRef = useRef<LeaguePrivateBetaJson | null>(null);

  const loadDashboard = useCallback(async (token: string, actorId: string, source: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch("/api/leagues/private-beta/my", {
        cache: "no-store",
        headers: { Authorization: `Bearer ${token}` },
      });
      const body = leagueBetaRecord(await response.json());
      if (!response.ok) throw new Error(leagueBetaText(body.message) || "No se pudo cargar Mis Ligas.");
      setData(body);
      setCached(false);
      writeCache(actorId, body);
      if (source === "realtime") setMessage("Ligas actualizadas desde el servidor.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo cargar Mis Ligas.");
    } finally {
      setLoading(false);
    }
  }, []);

  const loadWizard = useCallback(async (wizardId: string, token: string) => {
    if (!token) return;
    const response = await fetch(`/api/leagues/private-beta/wizard/${wizardId}`, {
      cache: "no-store",
      headers: { Authorization: `Bearer ${token}` },
    });
    const body = leagueBetaRecord(await response.json());
    if (!response.ok) throw new Error(leagueBetaText(body.message) || "No se pudo abrir el borrador.");
    const canonicalWizard = leagueBetaRecord(body.wizard);
    setWizard(canonicalWizard);
    setActiveStep(Math.min(Math.max(leagueBetaNumber(canonicalWizard.currentStep), 1), 12));
  }, []);

  useEffect(() => {
    wizardRef.current = wizard;
  }, [wizard]);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const sessionResult = await supabase?.auth.getSession();
      if (!active) return;
      const session = sessionResult?.data.session;
      if (!session) {
        setLoading(false);
        setMessage("Inicia sesión para consultar tu acceso a Ligas privadas.");
        return;
      }
      const token = session.access_token;
      const actorId = session.user.id;
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(actorId);
      if (local) {
        setData(local);
        setCached(true);
        setLoading(false);
      }
      await loadDashboard(token, actorId, "initial");
      if (!supabase) return;
      const reconcile = () => {
        void loadDashboard(token, actorId, "realtime");
        const currentWizard = wizardRef.current;
        if (currentWizard) void loadWizard(leagueBetaText(currentWizard.id), token);
      };
      window.addEventListener("online", reconcile);
      channel = supabase.channel(`league-private-beta:${actorId}`)
        .on("postgres_changes", {
          event: "INSERT",
          schema: "public",
          table: leaguePrivateBetaRealtimeTable,
        }, () => {
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => {
            void loadDashboard(token, actorId, "realtime");
            const currentWizard = wizardRef.current;
            if (currentWizard) void loadWizard(leagueBetaText(currentWizard.id), token);
          }, 120);
        })
        .subscribe((state) => { if (state === "SUBSCRIBED") reconcile(); });
      return () => window.removeEventListener("online", reconcile);
    };
    let removeOnlineListener: (() => void) | undefined;
    void start().then((cleanup) => {
      if (!active) cleanup?.();
      else removeOnlineListener = cleanup;
    });
    return () => {
      active = false;
      removeOnlineListener?.();
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  }, [loadDashboard, loadWizard]);

  async function command(action: LeaguePrivateBetaAction, aggregateId: string, expectedRevision: number, payload: LeaguePrivateBetaJson) {
    if (!accessToken || !userId) return;
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:league-private-beta-command", "/api/leagues/private-beta/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = leagueBetaRecord(await response.json());
      if (!response.ok) throw new Error(leagueBetaText(body.message) || "Operación no confirmada.");
      pending.current = null;
      const canonical = leagueBetaRecord(body.canonical);
      const snapshot = leagueBetaRecord(canonical.snapshot);
      const returnedWizard = action === "wizard.create"
        ? leagueBetaRecord(snapshot.wizard)
        : action === "wizard.finalize"
          ? leagueBetaRecord(snapshot.wizard)
          : snapshot;
      setMessage("Cambio confirmado por el servidor.");
      await loadDashboard(accessToken, userId, "mutation");
      if (action === "wizard.finalize" || action === "wizard.cancel") {
        setWizard(null);
      } else if (leagueBetaText(returnedWizard.id)) {
        setWizard(returnedWizard);
        setActiveStep(Math.min(Math.max(leagueBetaNumber(returnedWizard.currentStep), 1), 12));
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail)
        ? "La revisión cambió. Se ha recuperado el estado oficial."
        : detail);
      if (wizard && /STALE_REVISION|revision/i.test(detail)) {
        await loadWizard(leagueBetaText(wizard.id), accessToken);
      }
    } finally {
      setBusy(false);
    }
  }

  const flags = leagueBetaRecord(data?.flags);
  const organizers = leagueBetaArray(data?.organizers);
  const drafts = leagueBetaArray(data?.wizards).filter((item) => leagueBetaText(item.status) === "draft");
  const competitions = leagueBetaArray(data?.competitions);
  const eligibleOrganizers = organizers.filter((item) => leagueBetaBoolean(item.canCreate) && !leagueBetaBoolean(item.hasActiveLeague));
  const wizardSteps = leagueBetaRecord(wizard?.steps);
  const currentStepData = leagueBetaRecord(wizardSteps[String(activeStep)]);
  const wizardMode = (leagueBetaText(wizard?.authoringMode) === "ADVANCED" ? "ADVANCED" : "SIMPLE") as CompetitionAuthoringMode;

  function saveStep(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!wizard) return;
    void command("wizard.step.save", leagueBetaText(wizard.id), leagueBetaNumber(wizard.revision), {
      data: stepPayload(activeStep, new FormData(event.currentTarget), currentStepData),
      reason: `Wizard paso ${activeStep}`,
      step: activeStep,
    });
  }

  return <OfficialProductShellV2
    active="competir"
    perspective="league-organizer"
    context={{ detail: "Acceso por grant", eyebrow: "Competiciones", status: leagueBetaBoolean(flags.enabled) ? "Beta privada" : "Lectura", title: "Ligas (Beta)" }}
  >
    <main className={styles.page}>
      <GamePageHeader eyebrow="Producto privado" title="Ligas (Beta)" summary="Organiza una Liga por invitación sobre calendario, resultados y clasificación canónicos." />
      {cached ? <ProductFeedback tone="warning">Mostrando una copia local mientras se valida el estado oficial.</ProductFeedback> : null}
      {message ? <ProductFeedback tone={/confirmado|actualizadas/i.test(message) ? "success" : "info"}>{message}</ProductFeedback> : null}
      {loading ? <section className={styles.state}><strong>Cargando acceso...</strong></section> : null}
      {!loading && !accessToken ? <section className={styles.state}><strong>Beta por invitación</strong><p>Inicia sesión para comprobar si un Team o Club tiene acceso.</p><Link href="/">Volver a Inicio</Link></section> : null}

      {accessToken && !wizard ? <>
        <section className={styles.heroBand}>
          <div><span>League Wizard V2</span><h2>Reglas configurables, congeladas y auditables.</h2><p>Preset seguro, doce decisiones legibles y una única RuleRevision canónica.</p></div>
          <div className={styles.metrics}><MetricTile label="Mis Ligas" value={competitions.length} /><MetricTile label="Borradores" value={drafts.length} /><MetricTile label="Organizadores" value={organizers.length} /></div>
        </section>

        {eligibleOrganizers.length ? <section className={styles.primaryAction}><SectionHeader eyebrow="Siguiente acción" title="Crear Liga privada" /><p>Elige una base y el nivel de detalle. El preset se copia al borrador y deja de ser autoridad.</p><div className={styles.authoringControls}><label>Modo<select value={createMode} onChange={(event) => setCreateMode(event.target.value as CompetitionAuthoringMode)}><option value="SIMPLE">Sencillo</option><option value="ADVANCED">Avanzado</option></select></label><label>Preset<select value={createPreset} onChange={(event) => setCreatePreset(event.target.value)}>{leaguePrivateBetaPresets.map((preset) => <option key={preset.key} value={preset.key}>{preset.label}</option>)}</select></label></div><div className={styles.createGrid}>{eligibleOrganizers.map((organizer) => <button key={`${leagueBetaText(organizer.kind)}:${leagueBetaText(organizer.id)}`} type="button" disabled={busy} onClick={() => void command("wizard.create", leagueBetaText(organizer.id), leagueBetaNumber(organizer.organizerRevision), { authoringMode: createMode, organizerKind: leagueBetaText(organizer.kind), presetKey: createPreset, reason: "Inicio del wizard privado V2" })}><strong>{leagueBetaText(organizer.name)}</strong><span>{leagueBetaText(organizer.kind) === "CLUB" ? "Club" : "Equipo"} · hasta {leagueBetaNumber(leagueBetaRecord(organizer.bundle).teamCap)} equipos</span></button>)}</div></section> : organizers.length ? <section className={styles.accessState}><strong>Esta beta está disponible únicamente para organizadores autorizados.</strong><p>Puedes consultar tus Ligas y borradores, pero la creación requiere un bundle activo y no caducado.</p></section> : null}

        {drafts.length ? <section><SectionHeader eyebrow="Autoría" title="Borradores" /><div className={styles.cardGrid}>{drafts.map((draft) => <article className={styles.card} key={leagueBetaText(draft.id)}><div>{status(draft.status)}<span>Paso {leagueBetaNumber(draft.currentStep)} de 12</span></div><h3>Configuración sin publicar</h3><button type="button" disabled={busy} onClick={() => void loadWizard(leagueBetaText(draft.id), accessToken)}>Continuar</button></article>)}</div></section> : null}

        <section><SectionHeader eyebrow="Área privada" title="Mis Ligas" />{competitions.length ? <div className={styles.cardGrid}>{competitions.map((competition) => { const edition = leagueBetaRecord(competition.edition); const id = leagueBetaText(competition.id); return <article className={styles.leagueCard} key={id}><header><div>{status(competition.status)}<span>{leagueBetaText(edition.seasonLabel)}</span></div><h3>{leagueBetaText(competition.name)}</h3><p>{leagueBetaText(competition.generalArea) || "Zona por definir"} · {leagueBetaNumber(competition.entryCount)} equipos</p></header><div className={styles.leagueMetrics}><span><b>{leagueBetaNumber(competition.matchCount)}</b> partidos</span><span><b>{leagueBetaNumber(competition.pendingResultCount)}</b> resultados pendientes</span><span><b>{leagueBetaNumber(competition.incidentCount)}</b> incidencias</span></div><Link className={styles.primaryLink} href={`/competiciones/${id}/gestion/inscripciones`}>{leagueBetaNextActionLabel(competition.nextAction)}</Link><nav aria-label={`Gestión de ${leagueBetaText(competition.name)}`}><Link href={`/competiciones/${id}/configuracion`}>Configuración</Link><Link href={`/competiciones/${id}/gestion/inscripciones`}>Inscripciones</Link><Link href={`/competiciones/${id}/gestion/calendario`}>Calendario</Link><Link href={`/competiciones/${id}/gestion/resultados`}>Resultados</Link><Link href={`/competiciones/${id}/clasificacion`}>Clasificación</Link><Link href={`/competiciones/${id}/gestion/incidencias`}>Incidencias</Link></nav></article>; })}</div> : <div className={styles.empty}><strong>Aún no tienes Ligas.</strong><span>Cuando recibas acceso, la creación aparecerá como única siguiente acción.</span></div>}</section>

        <section className={styles.limits}><SectionHeader title="Alcance de la beta" /><div><span>4–20 equipos según bundle</span><span>Una Liga activa por organizador</span><span>Una o dos vueltas</span><span>Registro por invitación</span><span>Disciplina R5</span><span>Árbitros asignados</span></div><div className={styles.unavailable}><strong>Fuera de esta fase</strong><span>Pagos</span><span>Torneos</span><span>Pairing manual o híbrido</span><span>Superficies públicas</span></div></section>
      </> : null}

      {wizard ? <section className={styles.wizard}>
        <header className={styles.wizardHeader}><div><span>Borrador canónico · {wizardMode === "ADVANCED" ? "Avanzado" : "Sencillo"}</span><h2>{leaguePrivateBetaSteps[activeStep - 1]?.label}</h2><p>Cada paso se normaliza en PostgreSQL con revisión esperada.</p></div>{status(wizard.status)}</header>
        <div className={styles.wizardTools}><div role="group" aria-label="Modo de autoría"><button type="button" aria-pressed={wizardMode === "SIMPLE"} disabled={busy} onClick={() => void command("wizard.mode.set", leagueBetaText(wizard.id), leagueBetaNumber(wizard.revision), { mode: "SIMPLE", reason: "Modo sencillo" })}>Sencillo</button><button type="button" aria-pressed={wizardMode === "ADVANCED"} disabled={busy} onClick={() => void command("wizard.mode.set", leagueBetaText(wizard.id), leagueBetaNumber(wizard.revision), { mode: "ADVANCED", reason: "Modo avanzado" })}>Avanzado</button></div><label>Preset<select value={leagueBetaText(wizard.presetKey)} disabled={busy} onChange={(event) => void command("wizard.preset.apply", leagueBetaText(wizard.id), leagueBetaNumber(wizard.revision), { presetKey: event.target.value, reason: "Preset copiado al borrador" })}>{leaguePrivateBetaPresets.map((preset) => <option key={preset.key} value={preset.key}>{preset.label}</option>)}</select></label></div>
        <div className={styles.wizardBody}>
          <nav className={styles.stepRail} aria-label="Pasos de creación">{leaguePrivateBetaSteps.map((step) => { const done = Array.isArray(wizard.completedSteps) && (wizard.completedSteps as unknown[]).map(Number).includes(step.id); return <button type="button" key={step.id} aria-current={activeStep === step.id ? "step" : undefined} data-complete={done ? "true" : "false"} disabled={busy || step.id > Math.max(leagueBetaNumber(wizard.currentStep), 1)} onClick={() => setActiveStep(step.id)}><b>{step.id}</b><span>{step.label}</span></button>; })}</nav>
          <form className={styles.stepForm} key={`${leagueBetaText(wizard.id)}:${activeStep}:${leagueBetaNumber(wizard.revision)}`} onSubmit={saveStep}><div className={styles.fields}><WizardFields data={currentStepData} mode={wizardMode} step={activeStep} /></div><footer><button className={styles.secondary} type="button" disabled={busy} onClick={() => void command("wizard.cancel", leagueBetaText(wizard.id), leagueBetaNumber(wizard.revision), { reason: "Borrador cancelado por el organizador" })}>Cancelar borrador</button><button className={styles.primary} type="submit" disabled={busy}>Guardar y continuar</button>{activeStep === 12 && Array.isArray(wizard.completedSteps) && (wizard.completedSteps as unknown[]).map(Number).includes(12) ? <button className={styles.finalize} type="button" disabled={busy} onClick={() => void command("wizard.finalize", leagueBetaText(wizard.id), leagueBetaNumber(wizard.revision), { reason: "Reglamento V2 revisado y consentido" })}>Crear Liga privada</button> : null}</footer></form>
        </div>
      </section> : null}
    </main>
  </OfficialProductShellV2>;
}
