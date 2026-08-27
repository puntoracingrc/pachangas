"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type DragEvent,
  type FormEvent,
} from "react";
import {
  tournamentArray,
  tournamentBoolean,
  tournamentDrawModes,
  tournamentNumber,
  tournamentReadCacheVersion,
  tournamentRealtimeTable,
  tournamentRecord,
  tournamentStatusTone,
  tournamentText,
  tournamentWizardSteps,
  type TournamentDrawAction,
  type TournamentJson,
} from "../tournament-draw-contract";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  ResponsiveActionBar,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./tournament-private-beta-client.module.css";

export type TournamentSurface = "audit" | "desk" | "home" | "lab" | "participants" | "wizard";

type Props = {
  competitionId?: string;
  planId?: string;
  previewData?: TournamentJson | null;
  surface: TournamentSurface;
};

type CommandOptions = {
  action: TournamentDrawAction;
  aggregateId: string;
  expectedRevision: number;
  payload?: TournamentJson;
};

const cachePrefix = "pachangas-tournament-read-v1";
const wizardDraftKey = "pachangas-tournament-wizard-draft-v1";

function readCache(key: string) {
  try {
    const envelope = tournamentRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (tournamentNumber(envelope.version) !== tournamentReadCacheVersion) return null;
    return tournamentRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, data: TournamentJson) {
  try {
    window.localStorage.setItem(key, JSON.stringify({
      data,
      storedAt: new Date().toISOString(),
      version: tournamentReadCacheVersion,
    }));
  } catch {
    // This is a disposable read cache. PostgreSQL remains authoritative.
  }
}

function messageFrom(value: unknown, fallback: string) {
  const record = tournamentRecord(value);
  const detail = tournamentText(record.message) || tournamentText(record.error);
  if (!detail || /schema cache|function public\./i.test(detail)) return fallback;
  return detail.replaceAll("_", " ");
}

function status(value: unknown) {
  return <StatusChip tone={tournamentStatusTone(value)}>{tournamentText(value, "pendiente").replaceAll("_", " ")}</StatusChip>;
}

function competitionRevision(data: TournamentJson) {
  return tournamentNumber(
    data.expectedRevision,
    tournamentNumber(data.revision, tournamentNumber(tournamentRecord(data.competition).tournamentRevision)),
  );
}

function planFrom(data: TournamentJson) {
  return tournamentRecord(data.plan);
}

function cacheKey(surface: TournamentSurface, identity: string, userId: string) {
  return `${cachePrefix}:${surface}:${identity || "home"}:${userId || "anonymous"}`;
}

function routeFor(surface: TournamentSurface, competitionId: string, planId: string) {
  if (surface === "home" || surface === "wizard") return "/api/tournaments/home";
  if (surface === "participants") return `/api/tournaments/snapshot/${competitionId}`;
  if (surface === "audit") return planId
    ? `/api/tournaments/audit/${competitionId}/${planId}`
    : `/api/tournaments/snapshot/${competitionId}`;
  return planId
    ? `/api/tournaments/draw/${competitionId}/${planId}`
    : `/api/tournaments/snapshot/${competitionId}`;
}

function invalidationMatches(competitionId: string, payload: unknown) {
  if (!competitionId) return true;
  const row = tournamentRecord(tournamentRecord(payload).new);
  return tournamentText(row.competition_id) === competitionId;
}

export function TournamentPrivateBetaClient({ competitionId = "", planId = "", previewData = null, surface }: Props) {
  const router = useRouter();
  const preview = Boolean(previewData);
  const [data, setData] = useState<TournamentJson | null>(previewData);
  const [resolvedPlanId, setResolvedPlanId] = useState(planId);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(preview ? "Laboratorio aislado: ninguna acción escribe datos." : "");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);
  const identity = competitionId || "home";

  const loadCanonical = useCallback(async (
    token: string,
    actorId: string,
    source: "initial" | "mutation" | "realtime",
    requestedPlanId = resolvedPlanId,
  ) => {
    if (preview) return;
    try {
      let endpoint = routeFor(surface, competitionId, requestedPlanId);
      let response = await fetch(endpoint, {
        cache: "no-store",
        headers: { Authorization: `Bearer ${token}` },
      });
      let body = tournamentRecord(await response.json());
      if (!response.ok) throw new Error(messageFrom(body, "No se pudo recuperar el Torneo."));

      if ((surface === "desk" || surface === "audit") && !requestedPlanId) {
        const plans = tournamentArray(body.drawPlans).map(tournamentRecord);
        const selected = surface === "audit"
          ? plans.find((item) => tournamentText(item.status) === "published")
          : plans.at(-1);
        const selectedId = tournamentText(selected?.id);
        if (selectedId) {
          setResolvedPlanId(selectedId);
          endpoint = routeFor(surface, competitionId, selectedId);
          response = await fetch(endpoint, {
            cache: "no-store",
            headers: { Authorization: `Bearer ${token}` },
          });
          body = tournamentRecord(await response.json());
          if (!response.ok) throw new Error(messageFrom(body, "No se pudo recuperar el sorteo."));
        }
      }

      setData(body);
      setCached(false);
      writeCache(cacheKey(surface, identity, actorId), body);
      if (source === "realtime") setMessage("Estado actualizado desde PostgreSQL.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar el estado canónico.");
    } finally {
      setLoading(false);
    }
  }, [competitionId, identity, preview, resolvedPlanId, surface]);

  useEffect(() => {
    if (preview) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const session = await supabase?.auth.getSession();
      if (!active) return;
      const token = session?.data.session?.access_token ?? "";
      const actorId = session?.data.session?.user.id ?? "";
      if (!token || !actorId) {
        setLoading(false);
        setMessage("Inicia sesión para consultar Torneos privados.");
        return;
      }
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(cacheKey(surface, identity, actorId));
      if (local) {
        setData(local);
        setCached(true);
        setLoading(false);
      }
      await loadCanonical(token, actorId, "initial");
      if (!supabase) return;
      channel = supabase.channel(`tournament:${surface}:${identity}`)
        .on("system", {}, (payload) => {
          if (payload.extension === "postgres_changes" && payload.status === "ok") {
            void loadCanonical(token, actorId, "realtime");
          }
        })
        .on("postgres_changes", {
          event: "INSERT",
          schema: "public",
          table: tournamentRealtimeTable,
        }, (payload) => {
          if (!invalidationMatches(competitionId, payload)) return;
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(token, actorId, "realtime"), 120);
        })
        .subscribe((state) => {
          if (state === "SUBSCRIBED") void loadCanonical(token, actorId, "realtime");
        });
      const reconnect = () => void loadCanonical(token, actorId, "realtime");
      window.addEventListener("online", reconnect);
      return reconnect;
    };
    let reconnect: (() => void) | undefined;
    void start().then((callback) => { reconnect = callback; });
    return () => {
      active = false;
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
      if (reconnect) window.removeEventListener("online", reconnect);
    };
  }, [competitionId, identity, loadCanonical, preview, surface]);

  const command = useCallback(async ({ action, aggregateId, expectedRevision, payload = {} }: CommandOptions) => {
    if (preview) {
      setMessage("Laboratorio: la acción se ha simulado sin escritura remota.");
      return null;
    }
    if (!accessToken || !aggregateId) {
      setMessage("No hay sesión o contexto canónico para esta operación.");
      return null;
    }
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      setMessage("Sin conexión: puedes consultar la copia local, pero no modificar el Torneo.");
      return null;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:tournament-draw-command", "/api/tournaments/command", {
        body: JSON.stringify({
          action,
          aggregateId,
          expectedRevision,
          operationId: pending.current.id,
          payload,
        }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = tournamentRecord(await response.json());
      if (!response.ok) throw new Error(messageFrom(body, "Operación no confirmada."));
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await loadCanonical(accessToken, userId, "mutation");
      return tournamentRecord(body.canonical);
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE|revision/i.test(detail)
        ? "Otro dispositivo cambió la revisión. Se ha recuperado el estado oficial."
        : detail);
      if (/STALE|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
      return null;
    } finally {
      setBusy(false);
    }
  }, [accessToken, loadCanonical, preview, userId]);

  const content = <main className={styles.page} data-mobile-tab="equipo" data-tournament-surface={surface}>
    {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /sin conexión|no |error|stale|rechaz/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
    {loading && !data ? <div className={styles.empty}>Recuperando estado oficial...</div> : null}
    {!loading && !data ? <div className={styles.empty}>Torneos no disponible en este contexto.</div> : null}
    {data && surface === "home" ? <TournamentHome data={data} /> : null}
    {data && surface === "wizard" ? <TournamentWizard busy={busy} command={command} data={data} onCreated={(id) => router.push(`/competiciones/${id}/gestion/participantes`)} /> : null}
    {data && surface === "participants" ? <TournamentParticipants busy={busy} command={command} competitionId={competitionId} data={data} /> : null}
    {data && (surface === "desk" || surface === "lab") ? <TournamentDrawDesk busy={busy} command={command} competitionId={competitionId} data={data} preview={preview} /> : null}
    {data && surface === "audit" ? <TournamentAudit data={data} /> : null}
  </main>;

  return <OfficialProductShellV2
    active="equipo"
    context={{
      detail: preview ? "Laboratorio local" : cached ? "Copia local revalidándose" : "Servidor autoritativo",
      eyebrow: "Competiciones",
      status: preview ? "Solo visual" : loading ? "Sincronizando" : "Private Beta",
      title: surface === "wizard" ? "Crear Torneo" : surface === "participants" ? "Participantes" : surface === "desk" || surface === "lab" ? "Mesa de sorteo" : surface === "audit" ? "Sorteo publicado" : "Torneos",
    }}
  >{content}</OfficialProductShellV2>;
}

function TournamentHome({ data }: { data: TournamentJson }) {
  const flags = tournamentRecord(data.flags);
  const organizers = tournamentArray(data.organizers).map(tournamentRecord);
  const tournaments = tournamentArray(data.tournaments).map(tournamentRecord);
  const granted = organizers.some((organizer) => tournamentText(tournamentRecord(organizer.bundle).status) === "active");
  const creationEnabled = tournamentBoolean(flags.creationEnabled) && granted;
  return <>
    <GamePageHeader
      actions={creationEnabled ? <Link href="/torneos/crear">Crear Torneo</Link> : undefined}
      eyebrow="Private Beta"
      summary="Sorteos privados reproducibles, con participantes congelados y publicación auditable. Los partidos llegarán en una fase posterior."
      title="Torneos"
    />
    <section className={styles.metrics}>
      <MetricTile label="Mis Torneos" value={tournaments.length} />
      <MetricTile label="Borradores" value={tournaments.filter((item) => tournamentText(item.status) === "draft").length} />
      <MetricTile label="Sorteos" value={tournaments.filter((item) => Object.keys(tournamentRecord(item.drawPlan)).length).length} />
      <MetricTile label="Acceso" value={granted ? "Concedido" : "Por invitación"} />
    </section>
    {!creationEnabled ? <ProductFeedback tone="warning">Puedes consultar Torneos en los que participas. Crear uno requiere un grant privado para tu equipo o Club.</ProductFeedback> : null}
    <section className={styles.cardGrid}>
      {tournaments.map((item) => {
        const drawPlan = tournamentRecord(item.drawPlan);
        const id = tournamentText(item.id);
        return <article className={styles.tournamentCard} key={id}>
          <header><span>{tournamentText(item.organizerKind)}</span>{status(item.status)}</header>
          <h2>{tournamentText(item.name, "Torneo privado")}</h2>
          <p>{tournamentText(drawPlan.mode, "Sorteo sin preparar").replaceAll("_", " ")}</p>
          <footer>
            {tournamentBoolean(item.canManage) ? <Link href={`/competiciones/${id}/gestion/participantes`}>Participantes</Link> : null}
            {tournamentBoolean(item.canDraw) ? <Link href={`/competiciones/${id}/gestion/sorteo`}>Abrir sorteo</Link> : null}
            {tournamentText(drawPlan.status) === "published" ? <Link href={`/competiciones/${id}/sorteo`}>Ver sorteo</Link> : null}
          </footer>
        </article>;
      })}
      {!tournaments.length ? <div className={styles.empty}>Todavía no hay Torneos visibles para esta cuenta.</div> : null}
    </section>
  </>;
}

type WizardDraft = {
  description: string;
  drawMode: string;
  drawTarget: string;
  endsAt: string;
  generalArea: string;
  groupCount: number;
  modality: string;
  name: string;
  organizerId: string;
  organizerKind: string;
  participantCap: number;
  qualifiersPerGroup: number;
  seasonLabel: string;
  slug: string;
  startsAt: string;
};

const defaultDraft: WizardDraft = {
  description: "",
  drawMode: "SEEDED_POTS",
  drawTarget: "GROUP_ASSIGNMENT",
  endsAt: "",
  generalArea: "",
  groupCount: 4,
  modality: "FUTBOL_7",
  name: "",
  organizerId: "",
  organizerKind: "TEAM",
  participantCap: 16,
  qualifiersPerGroup: 2,
  seasonLabel: String(new Date().getFullYear()),
  slug: "",
  startsAt: "",
};

function TournamentWizard({ busy, command, data, onCreated }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<TournamentJson | null>;
  data: TournamentJson;
  onCreated: (competitionId: string) => void;
}) {
  const organizers = tournamentArray(data.organizers).map(tournamentRecord).filter((item) => tournamentText(tournamentRecord(item.bundle).status) === "active");
  const [step, setStep] = useState(1);
  const [draft, setDraft] = useState<WizardDraft>(() => {
    let initial = defaultDraft;
    if (typeof window !== "undefined") {
      try { initial = { ...defaultDraft, ...JSON.parse(window.localStorage.getItem(wizardDraftKey) ?? "{}") }; }
      catch { initial = defaultDraft; }
    }
    if (!initial.organizerId && organizers[0]) {
      return {
        ...initial,
        organizerId: tournamentText(organizers[0].id),
        organizerKind: tournamentText(organizers[0].kind),
      };
    }
    return initial;
  });
  useEffect(() => {
    try { window.localStorage.setItem(wizardDraftKey, JSON.stringify(draft)); } catch { /* Optional draft only. */ }
  }, [draft]);
  const organizer = organizers.find((item) => tournamentText(item.id) === draft.organizerId);
  const update = <K extends keyof WizardDraft>(key: K, value: WizardDraft[K]) => setDraft((current) => ({ ...current, [key]: value }));
  async function create() {
    if (!organizer || !draft.name.trim()) return;
    const canonical = await command({
      action: "tournament.create",
      aggregateId: draft.organizerId,
      expectedRevision: tournamentNumber(organizer.organizerRevision),
      payload: {
        ...draft,
        authoringMode: "ADVANCED",
        discipline: { enabled: false },
        editionName: `${draft.name} · Edición 1`,
        referees: { usage: "OPTIONAL" },
        registrationClosesAt: draft.startsAt ? `${draft.startsAt}T00:00:00.000Z` : undefined,
        reason: "Creación desde Tournament Wizard V1",
        slug: draft.slug || draft.name.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""),
      },
    });
    const id = tournamentText(tournamentRecord(tournamentRecord(canonical?.snapshot).competition).id);
    if (id) {
      window.localStorage.removeItem(wizardDraftKey);
      onCreated(id);
    }
  }
  return <>
    <GamePageHeader eyebrow="Tournament Wizard V1" summary="El borrador vive en este dispositivo; el Torneo existe solo después de la confirmación del servidor." title="Crear Torneo privado" />
    <nav className={styles.stepRail} aria-label="Pasos del asistente">
      {tournamentWizardSteps.map((item) => <button aria-current={step === item.id ? "step" : undefined} key={item.id} onClick={() => setStep(item.id)} type="button"><b>{item.id}</b><span>{item.label}</span></button>)}
    </nav>
    <section className={styles.wizardPanel}>
      <SectionHeader eyebrow={`Paso ${step} de 12`} title={tournamentWizardSteps[step - 1]?.label ?? "Revisión"} />
      {step === 1 ? <div className={styles.formGrid}>
        <label>Organizador<select value={draft.organizerId} onChange={(event) => {
          const next = organizers.find((item) => tournamentText(item.id) === event.target.value);
          update("organizerId", event.target.value); update("organizerKind", tournamentText(next?.kind, "TEAM"));
        }}>{organizers.map((item) => <option key={tournamentText(item.id)} value={tournamentText(item.id)}>{tournamentText(item.name)} · {tournamentText(item.kind)}</option>)}</select></label>
        <label>Nombre<input value={draft.name} onChange={(event) => update("name", event.target.value)} /></label>
        <label>Zona<input value={draft.generalArea} onChange={(event) => update("generalArea", event.target.value)} /></label>
        <label className={styles.fullField}>Descripción<textarea value={draft.description} onChange={(event) => update("description", event.target.value)} /></label>
      </div> : null}
      {step === 2 ? <RadioSet label="Modalidad" options={["FUTSAL", "FUTBOL_5", "FUTBOL_7", "FUTBOL_11"]} value={draft.modality} onChange={(value) => update("modality", value)} /> : null}
      {step === 3 ? <div className={styles.formGrid}><label>Temporada<input value={draft.seasonLabel} onChange={(event) => update("seasonLabel", event.target.value)} /></label><label>Inicio<input type="date" value={draft.startsAt} onChange={(event) => update("startsAt", event.target.value)} /></label><label>Fin<input type="date" value={draft.endsAt} onChange={(event) => update("endsAt", event.target.value)} /></label></div> : null}
      {step === 4 || step === 6 ? <RadioSet label="Estructura inicial" options={["GROUP_ASSIGNMENT", "KNOCKOUT_INITIAL_SEEDING", "GROUPS_THEN_KNOCKOUT"]} value={draft.drawTarget} onChange={(value) => update("drawTarget", value)} /> : null}
      {step === 5 ? <div className={styles.formGrid}><label>Máximo de equipos<input max={64} min={4} type="number" value={draft.participantCap} onChange={(event) => update("participantCap", Number(event.target.value))} /></label></div> : null}
      {step === 6 ? <div className={styles.formGrid}><label>Grupos<input max={16} min={1} type="number" value={draft.groupCount} onChange={(event) => update("groupCount", Number(event.target.value))} /></label><label>Clasificados por grupo<input max={16} min={1} type="number" value={draft.qualifiersPerGroup} onChange={(event) => update("qualifiersPerGroup", Number(event.target.value))} /></label></div> : null}
      {step === 7 ? <p className={styles.stepCopy}>Los bombos y cabezas de serie se definirán con los participantes aceptados, antes de generar el sorteo.</p> : null}
      {step === 8 ? <RadioSet label="Modo" options={[...tournamentDrawModes]} value={draft.drawMode} onChange={(value) => update("drawMode", value)} /> : null}
      {step === 9 ? <p className={styles.stepCopy}>Podrás añadir separación por Club, equilibrio de nivel, distribución de bombos y restricciones manuales en la mesa.</p> : null}
      {step === 10 ? <p className={styles.stepCopy}>R6A conserva el contrato deportivo y no genera partidos, resultados ni clasificación.</p> : null}
      {step === 11 ? <p className={styles.stepCopy}>Disciplina y uso arbitral quedan registrados en la RuleRevision; las asignaciones de partidos de Torneo siguen apagadas.</p> : null}
      {step === 12 ? <div className={styles.reviewGrid}>{Object.entries({ Organizador: tournamentText(organizer?.name), Nombre: draft.name, Modalidad: draft.modality, Formato: draft.drawTarget, Equipos: draft.participantCap, Grupos: draft.groupCount, Modo: draft.drawMode }).map(([label, value]) => <div key={label}><span>{label}</span><strong>{String(value || "Pendiente")}</strong></div>)}</div> : null}
      <ResponsiveActionBar><button disabled={step === 1 || busy} onClick={() => setStep((value) => Math.max(1, value - 1))} type="button">Anterior</button>{step < 12 ? <button onClick={() => setStep((value) => Math.min(12, value + 1))} type="button">Siguiente</button> : <button disabled={busy || !organizer || !draft.name.trim()} onClick={() => void create()} type="button">Crear en servidor</button>}</ResponsiveActionBar>
    </section>
  </>;
}

function RadioSet({ label, onChange, options, value }: { label: string; onChange: (value: string) => void; options: readonly string[]; value: string }) {
  return <fieldset className={styles.segmented}><legend>{label}</legend>{options.map((option) => <button aria-pressed={value === option} key={option} onClick={() => onChange(option)} type="button">{option.replaceAll("_", " ")}</button>)}</fieldset>;
}

function TournamentParticipants({ busy, command, competitionId, data }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<TournamentJson | null>;
  competitionId: string;
  data: TournamentJson;
}) {
  const competition = tournamentRecord(data.competition);
  const capabilities = tournamentRecord(data.capabilities);
  const entries = tournamentArray(data.entries).map(tournamentRecord);
  const plans = tournamentArray(data.drawPlans).map(tournamentRecord);
  const [teamId, setTeamId] = useState("");
  function invite(event: FormEvent) {
    event.preventDefault();
    void command({ action: "participant.invite", aggregateId: competitionId, expectedRevision: competitionRevision(data), payload: { teamId, reason: "Invitación desde la mesa de participantes" } });
    setTeamId("");
  }
  return <>
    <GamePageHeader actions={<Link href={`/competiciones/${competitionId}/gestion/sorteo`}>Abrir sorteo</Link>} eyebrow={tournamentText(competition.name)} summary="Solo los equipos aceptados podrán entrar en el freeze inmutable del sorteo." title="Participantes" />
    <section className={styles.metrics}><MetricTile label="Invitados" value={entries.filter((item) => tournamentText(item.status) === "invited").length} /><MetricTile label="Aceptados" value={entries.filter((item) => ["accepted", "active"].includes(tournamentText(item.status))).length} /><MetricTile label="Planes" value={plans.length} /><MetricTile label="Revisión" value={competitionRevision(data)} /></section>
    {tournamentBoolean(capabilities.participantsManage) ? <form className={styles.inviteBar} onSubmit={invite}><label>ID del equipo<input pattern="[0-9a-fA-F-]{36}" required value={teamId} onChange={(event) => setTeamId(event.target.value)} /></label><button disabled={busy || !teamId} type="submit">Invitar equipo</button></form> : null}
    <section className={styles.participantList}>{entries.map((entry) => <article key={tournamentText(entry.id)}><div className={styles.teamMark}>{tournamentText(entry.teamName).slice(0, 2).toUpperCase()}</div><div><strong>{tournamentText(entry.teamName)}</strong><small>{tournamentText(entry.teamId)}</small></div>{status(entry.status)}</article>)}{!entries.length ? <div className={styles.empty}>Todavía no hay equipos invitados.</div> : null}</section>
  </>;
}

function TournamentDrawDesk({ busy, command, competitionId, data, preview }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<TournamentJson | null>;
  competitionId: string;
  data: TournamentJson;
  preview: boolean;
}) {
  const plan = planFrom(data);
  const context = tournamentRecord(data.authoringContext);
  const plans = tournamentArray(data.drawPlans).map(tournamentRecord);
  const setupPlan = !tournamentText(plan.id) ? plans.at(-1) ?? {} : plan;
  const freeze = tournamentRecord(data.participantFreeze);
  const frozenEntries = tournamentArray(freeze.entries).map(tournamentRecord);
  const placements = tournamentArray(plan.placements).map(tournamentRecord);
  const pots = tournamentArray(plan.pots).map(tournamentRecord);
  const constraints = tournamentArray(plan.constraints).map(tournamentRecord);
  const locks = tournamentArray(plan.manualLocks).map(tournamentRecord);
  const quality = tournamentRecord(plan.quality);
  const revision = tournamentRecord(plan.revisionSnapshot);
  const capabilities = tournamentRecord(data.capabilities);
  const [tab, setTab] = useState<"groups" | "participants" | "rules">("groups");
  const [selectedEntryId, setSelectedEntryId] = useState("");
  const [reveal, setReveal] = useState(false);
  const entryMap = new Map(frozenEntries.map((entry) => [tournamentText(entry.entryId), entry]));
  const groupCount = Math.max(1, tournamentNumber(plan.groupCount, 4));
  const groups = Array.from({ length: groupCount }, (_, index) => index + 1);
  const expectedRevision = competitionRevision(data);
  const editable = preview || (tournamentBoolean(capabilities.manage) && !["published", "cancelled"].includes(tournamentText(plan.status)));

  async function createPlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const source = Object.keys(context).length ? context : tournamentRecord(data.authoringContext);
    await command({
      action: "draw_plan.create",
      aggregateId: competitionId,
      expectedRevision,
      payload: {
        editionId: tournamentText(source.editionId),
        groupCount: Number(form.get("groupCount")),
        mode: String(form.get("mode")),
        qualifiersPerGroup: Number(form.get("qualifiersPerGroup")),
        reason: "Creación de DrawPlan desde Draw Desk",
        ruleRevisionId: tournamentText(source.ruleRevisionId),
        stageId: tournamentText(source.stageId),
        targetType: String(form.get("targetType")),
      },
    });
  }

  function moveEntry(entryId: string, groupNumber: number, slotNumber: number) {
    if (!editable || !entryId) return;
    const occupant = placements.find((placement) => (
      tournamentNumber(placement.groupNumber) === groupNumber
      && tournamentNumber(placement.slotNumber) === slotNumber
      && tournamentText(placement.entryId) !== entryId
    ));
    void command({
      action: occupant
        ? "draw.entry.swap"
        : placements.some((placement) => tournamentText(placement.entryId) === entryId) ? "draw.entry.move" : "draw.entry.place",
      aggregateId: competitionId,
      expectedRevision,
      payload: occupant
        ? { entryId, otherEntryId: tournamentText(occupant.entryId), planId: tournamentText(plan.id), reason: "Intercambio manual en Draw Desk" }
        : { entryId, groupNumber, planId: tournamentText(plan.id), reason: "Colocación manual en Draw Desk", slotNumber },
    });
  }

  function generateDraw() {
    void command({
      action: tournamentText(revision.id) ? "draw.regenerate" : "draw.generate",
      aggregateId: competitionId,
      expectedRevision,
      payload: {
        planId: tournamentText(plan.id),
        publicSeed: `pachangas-${crypto.randomUUID()}`,
        reason: "Generación desde Draw Desk",
        seedMode: "CUSTOM_PUBLIC_SEED",
      },
    });
  }

  if (!tournamentText(plan.id) && !tournamentText(setupPlan.id)) return <>
    <GamePageHeader eyebrow="Tournament Draw V1" summary="Primero crea un plan autoritativo sobre la edición y RuleRevision actuales." title="Preparar sorteo" />
    <form className={styles.setupPanel} onSubmit={createPlan}>
      <label>Objetivo<select name="targetType"><option value="GROUP_ASSIGNMENT">Grupos</option><option value="KNOCKOUT_INITIAL_SEEDING">Cuadro inicial</option><option value="GROUPS_THEN_KNOCKOUT">Grupos y clasificación futura</option></select></label>
      <label>Modo<select name="mode">{tournamentDrawModes.map((mode) => <option key={mode}>{mode}</option>)}</select></label>
      <label>Grupos<input defaultValue={4} max={16} min={1} name="groupCount" type="number" /></label>
      <label>Clasificados<input defaultValue={2} max={16} min={1} name="qualifiersPerGroup" type="number" /></label>
      <button disabled={busy || !tournamentText(context.editionId)} type="submit">Crear plan canónico</button>
    </form>
  </>;

  if (!tournamentText(plan.id) && tournamentText(setupPlan.id)) return <div className={styles.empty}>Abriendo el último plan del Torneo...</div>;

  return <>
    <GamePageHeader actions={<><Link href={`/competiciones/${competitionId}/gestion/participantes`}>Participantes</Link>{tournamentText(plan.status) === "published" ? <Link href={`/competiciones/${competitionId}/sorteo`}>Audit view</Link> : null}</>} eyebrow="Tournament Draw V1" summary="Cada movimiento confirmado crea evidencia; la mesa relee el snapshot canónico después de Realtime." title="Mesa de sorteo" />
    <section className={styles.metrics}><MetricTile label="Estado" value={status(plan.status)} /><MetricTile label="Modo" value={tournamentText(plan.mode).replaceAll("_", " ")} /><MetricTile label="Participantes" value={tournamentNumber(freeze.participantCount)} /><MetricTile label="Quality" value={quality.softScore == null ? "—" : tournamentNumber(quality.softScore).toFixed(1)} /></section>
    <nav className={styles.portraitTabs} aria-label="Panel de la mesa"><button aria-pressed={tab === "participants"} onClick={() => setTab("participants")} type="button">Equipos</button><button aria-pressed={tab === "groups"} onClick={() => setTab("groups")} type="button">Sorteo</button><button aria-pressed={tab === "rules"} onClick={() => setTab("rules")} type="button">Reglas</button></nav>
    <section className={styles.drawDesk}>
      <aside className={styles.participantRail} data-mobile-open={tab === "participants"}>
        <SectionHeader eyebrow="Freeze" title={`${frozenEntries.length} equipos`} />
        <div className={styles.availableEntries}>{frozenEntries.map((entry) => {
          const id = tournamentText(entry.entryId);
          const placed = placements.some((item) => tournamentText(item.entryId) === id);
          return <button aria-pressed={selectedEntryId === id} draggable={editable} key={id} onClick={() => setSelectedEntryId(id)} onDragStart={(event) => event.dataTransfer.setData("text/tournament-entry", id)} type="button"><span>{tournamentText(entry.teamName).slice(0, 2).toUpperCase()}</span><strong>{tournamentText(entry.teamName)}</strong><small>{placed ? "Colocado" : "Disponible"}</small></button>;
        })}</div>
        {!frozenEntries.length && editable ? <button disabled={busy} onClick={() => void command({ action: "participants.freeze", aggregateId: competitionId, expectedRevision, payload: { planId: tournamentText(plan.id), reason: "Freeze desde Draw Desk" } })} type="button">Congelar participantes</button> : null}
        {frozenEntries.length && editable ? <button disabled={busy} onClick={() => void command({ action: "participants.unfreeze", aggregateId: competitionId, expectedRevision, payload: { planId: tournamentText(plan.id), reason: "Reabrir participantes" } })} type="button">Reabrir participantes</button> : null}
      </aside>
      <section className={styles.groupBoard} data-mobile-open={tab === "groups"} data-reveal={reveal ? "true" : "false"}>
        <div className={styles.boardToolbar}><strong>{tournamentText(revision.resultChecksum) ? `Resultado ${tournamentText(revision.resultChecksum).slice(0, 8)}` : "Resultado sin generar"}</strong>{placements.length ? <button aria-pressed={reveal} onClick={() => setReveal((value) => !value)} type="button">{reveal ? "Resultado completo" : "Revelar"}</button> : null}</div>
        <div className={styles.groups}>{groups.map((groupNumber) => {
          const groupPlacements = placements.filter((item) => tournamentNumber(item.groupNumber) === groupNumber).sort((a, b) => tournamentNumber(a.slotNumber) - tournamentNumber(b.slotNumber));
          const size = Math.max(Math.ceil(Math.max(frozenEntries.length, groupCount * 4) / groupCount), groupPlacements.length);
          return <article className={styles.group} key={groupNumber}><header><span>Grupo</span><strong>{String.fromCharCode(64 + groupNumber)}</strong></header>{Array.from({ length: size }, (_, index) => {
            const slot = index + 1;
            const placement = groupPlacements.find((item) => tournamentNumber(item.slotNumber) === slot);
            const id = tournamentText(placement?.entryId);
            const entry = entryMap.get(id);
            const revealIndex = (groupNumber - 1) * size + index;
            return <button
              className={styles.slot}
              data-filled={id ? "true" : "false"}
              draggable={editable && Boolean(id)}
              key={slot}
              onClick={() => selectedEntryId && moveEntry(selectedEntryId, groupNumber, slot)}
              onDragOver={(event) => event.preventDefault()}
              onDragStart={(event) => event.dataTransfer.setData("text/tournament-entry", id)}
              onDrop={(event: DragEvent<HTMLButtonElement>) => { event.preventDefault(); moveEntry(event.dataTransfer.getData("text/tournament-entry"), groupNumber, slot); }}
              style={{ "--reveal-index": revealIndex } as CSSProperties}
              type="button"
            >{id ? <><span>{tournamentText(entry?.teamName).slice(0, 2).toUpperCase()}</span><strong>{tournamentText(entry?.teamName, id.slice(0, 8))}</strong><small>B{tournamentNumber(placement?.potNumber) || "—"} · {tournamentText(placement?.placementSource, "ENGINE")}</small></> : <><span>{slot}</span><strong>Posición libre</strong><small>Suelta un equipo</small></>}</button>;
          })}</article>;
        })}</div>
      </section>
      <aside className={styles.ruleRail} data-mobile-open={tab === "rules"}>
        <SectionHeader eyebrow="Control" title="Reglas y calidad" />
        <dl className={styles.qualityList}><div><dt>Hard violations</dt><dd>{tournamentNumber(quality.hardViolations)}</dd></div><div><dt>Balance</dt><dd>{tournamentNumber(quality.levelBalance).toFixed(1)}</dd></div><div><dt>Club collisions</dt><dd>{tournamentNumber(quality.sameClubCollisions)}</dd></div><div><dt>Overrides</dt><dd>{tournamentNumber(quality.manualOverrideCount)}</dd></div></dl>
        <PotControls busy={busy} command={command} competitionId={competitionId} entries={frozenEntries} expectedRevision={expectedRevision} plan={plan} pots={pots} />
        <ConstraintControls busy={busy} command={command} competitionId={competitionId} constraints={constraints} expectedRevision={expectedRevision} plan={plan} />
        <div className={styles.lockList}><strong>{locks.length} locks</strong>{locks.slice(0, 6).map((lock) => <span key={tournamentText(lock.id)}>{tournamentText(lock.lockType).replaceAll("_", " ")}</span>)}</div>
      </aside>
    </section>
    {editable ? <ResponsiveActionBar>
      <button disabled={busy || !frozenEntries.length} onClick={generateDraw} type="button">{tournamentText(revision.id) ? "Regenerar" : "Generar"}</button>
      <button disabled={busy || !selectedEntryId} onClick={() => {
        const placement = placements.find((item) => tournamentText(item.entryId) === selectedEntryId);
        void command({ action: "draw.lock.create", aggregateId: competitionId, expectedRevision, payload: { entryId: selectedEntryId, groupNumber: tournamentNumber(placement?.groupNumber), lockType: "ENTRY_TO_GROUP", planId: tournamentText(plan.id), reason: "Lock desde Draw Desk" } });
      }} type="button">Bloquear selección</button>
      <button disabled={busy || !tournamentText(revision.id)} onClick={() => void command({ action: "draw.validate", aggregateId: competitionId, expectedRevision, payload: { planId: tournamentText(plan.id), reason: "Validación desde Draw Desk" } })} type="button">Validar</button>
      <button disabled={busy || tournamentText(plan.status) !== "validated" || !tournamentBoolean(capabilities.publish)} onClick={() => void command({ action: "draw.publish", aggregateId: competitionId, expectedRevision, payload: { planId: tournamentText(plan.id), reason: "Publicación desde Draw Desk" } })} type="button">Publicar</button>
    </ResponsiveActionBar> : null}
  </>;
}

function PotControls({ busy, command, competitionId, entries, expectedRevision, plan, pots }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<TournamentJson | null>;
  competitionId: string;
  entries: TournamentJson[];
  expectedRevision: number;
  plan: TournamentJson;
  pots: TournamentJson[];
}) {
  const [potNumber, setPotNumber] = useState(pots.length + 1);
  const selected = entries.filter((_, index) => index % Math.max(1, tournamentNumber(plan.groupCount, 4)) === (potNumber - 1) % Math.max(1, tournamentNumber(plan.groupCount, 4))).map((entry) => tournamentText(entry.entryId));
  return <div className={styles.toolBlock}><strong>Bombos</strong><label>Número<input min={1} max={64} type="number" value={potNumber} onChange={(event) => setPotNumber(Number(event.target.value))} /></label><button disabled={busy || !entries.length} onClick={() => void command({ action: "draw_pot.create", aggregateId: competitionId, expectedRevision, payload: { capacity: Math.max(1, selected.length), entryIds: selected, label: `Bombo ${potNumber}`, planId: tournamentText(plan.id), potNumber, reason: "Bombo creado en Draw Desk", seedingPolicy: "MANUAL" } })} type="button">Crear Bombo {potNumber}</button><small>{pots.length} configurados</small></div>;
}

function ConstraintControls({ busy, command, competitionId, constraints, expectedRevision, plan }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<TournamentJson | null>;
  competitionId: string;
  constraints: TournamentJson[];
  expectedRevision: number;
  plan: TournamentJson;
}) {
  const [type, setType] = useState("POT_DISTRIBUTION");
  return <div className={styles.toolBlock}><strong>Constraints</strong><select value={type} onChange={(event) => setType(event.target.value)}><option>POT_DISTRIBUTION</option><option>SAME_CLUB_AVOIDANCE</option><option>TEAM_LEVEL_BALANCE</option><option>MANUAL_SEPARATION</option></select><button disabled={busy} onClick={() => void command({ action: "draw_constraint.create", aggregateId: competitionId, expectedRevision, payload: { constraintType: type, parameters: {}, planId: tournamentText(plan.id), publicAttribution: true, reason: "Regla configurada en Draw Desk", scope: "DRAW", strength: type === "TEAM_LEVEL_BALANCE" ? "SOFT" : "HARD", weight: type === "TEAM_LEVEL_BALANCE" ? 50 : 1000 } })} type="button">Añadir</button><small>{constraints.length} activas</small></div>;
}

function TournamentAudit({ data }: { data: TournamentJson }) {
  const placements = tournamentArray(data.placements).map(tournamentRecord);
  const constraints = tournamentArray(data.constraints).map(tournamentRecord);
  const [reveal, setReveal] = useState(false);
  const groupNumbers = [...new Set(placements.map((item) => tournamentNumber(item.groupNumber)).filter(Boolean))];
  const revealOrder = new Map(placements.map((item, index) => [tournamentText(item.entryId), index]));
  if (!tournamentText(data.drawPlanId)) return <><GamePageHeader eyebrow="Tournament Draw" title="Sorteo" /><div className={styles.empty}>No hay un sorteo publicado para este Torneo.</div></>;
  return <>
    <GamePageHeader actions={<button aria-pressed={reveal} onClick={() => setReveal((value) => !value)} type="button">{reveal ? "Resultado completo" : "Revelar sorteo"}</button>} eyebrow="Evidencia pública para participantes" summary="La animación reproduce un resultado ya fijado; nunca genera ni altera el sorteo." title="Sorteo publicado" />
    <section className={styles.metrics}><MetricTile label="Modo" value={tournamentText(data.mode).replaceAll("_", " ")} /><MetricTile label="Algoritmo" value={tournamentText(data.algorithmVersion)} /><MetricTile label="Revisión" value={tournamentNumber(data.version)} /><MetricTile label="Overrides" value={tournamentNumber(data.manualOverrideCount)} /></section>
    <section className={styles.auditBoard} data-reveal={reveal ? "true" : "false"}>
      {groupNumbers.map((group) => (
        <article key={group}>
          <header>Grupo {String.fromCharCode(64 + group)}</header>
          {placements
            .filter((item) => tournamentNumber(item.groupNumber) === group)
            .map((item) => (
              <div key={tournamentText(item.entryId)} style={{ "--reveal-index": revealOrder.get(tournamentText(item.entryId)) ?? 0 } as CSSProperties}>
                <span>{tournamentNumber(item.slotNumber)}</span>
                <strong>{tournamentText(item.teamName, tournamentText(item.entryId).slice(0, 8))}</strong>
              </div>
            ))}
        </article>
      ))}
    </section>
    <section className={styles.auditEvidence}>
      <SectionHeader eyebrow="Trazabilidad" title="Cómo se obtuvo" />
      <dl>
        <div><dt>Seed</dt><dd>{tournamentText(data.seed)}</dd></div>
        <div><dt>Input</dt><dd>{tournamentText(data.inputChecksum)}</dd></div>
        <div><dt>Resultado</dt><dd>{tournamentText(data.resultChecksum)}</dd></div>
        <div><dt>Servidor</dt><dd>{tournamentNumber(data.serverSequence)}</dd></div>
      </dl>
      <div>{constraints.map((item, index) => (
        <StatusChip key={`${tournamentText(item.type)}-${index}`} tone="info">
          {tournamentText(item.type).replaceAll("_", " ")}
        </StatusChip>
      ))}</div>
      <Link href="/torneos">Volver a Torneos</Link>
    </section>
  </>;
}
