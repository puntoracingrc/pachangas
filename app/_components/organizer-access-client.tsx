"use client";

import Link from "next/link";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type MutableRefObject,
  type ReactNode,
} from "react";
import {
  organizerAccessArray,
  organizerAccessBoolean,
  organizerAccessCacheKey,
  organizerAccessDate,
  organizerAccessNextActionLabel,
  organizerAccessNumber,
  organizerAccessRealtimeTable,
  organizerAccessRecord,
  organizerAccessStatusLabel,
  organizerAccessText,
  organizerAccessTone,
  type OrganizerAccessAction,
  type OrganizerAccessJson,
} from "../organizer-access-contract";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import styles from "./organizer-access.module.css";

type Surface = "apply" | "detail" | "launcher" | "list" | "onboarding";
type PendingOperation = { id: string; key: string };

type ApplicationForm = {
  area: string;
  competitionType: "BOTH" | "LEAGUE" | "TOURNAMENT";
  fieldRelationship: string;
  intent: "BOTH" | "LEAGUE" | "TOURNAMENT";
  municipality: string;
  summary: string;
  targetStartDate: string;
  teamCount: string;
};

const emptyForm: ApplicationForm = {
  area: "",
  competitionType: "BOTH",
  fieldRelationship: "",
  intent: "BOTH",
  municipality: "",
  summary: "",
  targetStartDate: "",
  teamCount: "",
};

const checkpointLabels: Record<string, string> = {
  FIRST_COMPETITION_DRAFT: "Primera competición en borrador",
  FIRST_MATCH_PREPARED: "Primer partido preparado",
  ORGANIZER_ACCESS: "Acceso de organizador vigente",
  ORGANIZER_ACTIVE: "Club o equipo activo",
  ORGANIZER_IDENTITY: "Identidad del organizador",
  ORGANIZER_PROFILE: "Perfil configurado",
  PARTICIPANTS: "Participantes o invitaciones",
  PUBLICATION: "Publicación o uso privado confirmado",
  SCHEDULE_OR_DRAW: "Calendario o sorteo",
  VALID_RULE_REVISION: "Reglamento válido",
};

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

async function readJson(response: Response) {
  const body = organizerAccessRecord(await response.json().catch(() => ({})));
  if (!response.ok) {
    const message = organizerAccessText(body.message, organizerAccessText(body.error, "Operación no confirmada."));
    if (organizerAccessText(body.error) === "CLIENT_UPDATE_REQUIRED") {
      throw new Error("Actualiza Pachangas IQ antes de volver a guardar cambios.");
    }
    throw new Error(message);
  }
  return body;
}

function readCache(actorId: string) {
  try {
    return organizerAccessRecord(JSON.parse(window.localStorage.getItem(organizerAccessCacheKey(actorId)) ?? "null"));
  } catch {
    return {};
  }
}

function writeCache(actorId: string, canonical: OrganizerAccessJson) {
  try {
    window.localStorage.setItem(organizerAccessCacheKey(actorId), JSON.stringify({ canonical, savedAt: new Date().toISOString() }));
  } catch {
    // This cache is optional and never authorizes a write.
  }
}

function operationFor(ref: MutableRefObject<PendingOperation | null>, key: string) {
  if (!ref.current || ref.current.key !== key) ref.current = { id: crypto.randomUUID(), key };
  return ref.current.id;
}

function formFromApplication(application: OrganizerAccessJson): ApplicationForm {
  const competitionType = organizerAccessText(application.expectedCompetitionType, "BOTH");
  const intent = organizerAccessText(application.intent, "BOTH");
  return {
    area: organizerAccessText(application.area),
    competitionType: (["LEAGUE", "TOURNAMENT"] as const).includes(competitionType as "LEAGUE" | "TOURNAMENT") ? competitionType as "LEAGUE" | "TOURNAMENT" : "BOTH",
    fieldRelationship: organizerAccessText(application.fieldRelationship),
    intent: (["LEAGUE", "TOURNAMENT"] as const).includes(intent as "LEAGUE" | "TOURNAMENT") ? intent as "LEAGUE" | "TOURNAMENT" : "BOTH",
    municipality: organizerAccessText(application.municipality),
    summary: organizerAccessText(application.summary),
    targetStartDate: organizerAccessText(application.targetStartDate),
    teamCount: application.expectedTeamCount == null ? "" : String(application.expectedTeamCount),
  };
}

function formPayload(form: ApplicationForm) {
  return {
    ...form,
    teamCount: form.teamCount ? Number(form.teamCount) : "",
  };
}

function Status({ value }: { value: unknown }) {
  return <span className={styles.status} data-tone={organizerAccessTone(value)}>{organizerAccessStatusLabel(value)}</span>;
}

function OrganizerNavigation({ surface }: { surface: Surface }) {
  const links = [
    { href: "/organizacion/solicitar-acceso", id: "apply", label: "Solicitar acceso" },
    { href: "/organizacion/solicitudes", id: "list", label: "Solicitudes" },
    { href: "/organizacion/onboarding", id: "onboarding", label: "Onboarding" },
    { href: "/organizacion/empezar", id: "launcher", label: "Empezar" },
    { href: "/planes-organizador", id: "plans", label: "Planes" },
  ];
  return <nav className={styles.subnav} aria-label="Organización">{links.map((item) => <Link data-active={surface === item.id || (surface === "detail" && item.id === "list")} href={item.href} key={item.id}>{item.label}</Link>)}</nav>;
}

function ApplicationFields({ disabled, form, setForm }: { disabled: boolean; form: ApplicationForm; setForm: (next: ApplicationForm) => void }) {
  return <div className={styles.formGrid}>
    <label className={styles.field}>Qué quieres organizar<select disabled={disabled} value={form.intent} onChange={(event) => setForm({ ...form, intent: event.target.value as ApplicationForm["intent"] })}><option value="BOTH">Liga y Torneo</option><option value="LEAGUE">Liga</option><option value="TOURNAMENT">Torneo</option></select></label>
    <label className={styles.field}>Primera competición<select disabled={disabled} value={form.competitionType} onChange={(event) => setForm({ ...form, competitionType: event.target.value as ApplicationForm["competitionType"] })}><option value="BOTH">Por decidir</option><option value="LEAGUE">Liga</option><option value="TOURNAMENT">Torneo</option></select></label>
    <label className={styles.field}>Equipos previstos<input disabled={disabled} min={2} max={10000} inputMode="numeric" type="number" value={form.teamCount} onChange={(event) => setForm({ ...form, teamCount: event.target.value })} /></label>
    <label className={styles.field}>Fecha aproximada<input disabled={disabled} type="date" value={form.targetStartDate} onChange={(event) => setForm({ ...form, targetStartDate: event.target.value })} /></label>
    <label className={styles.field}>Municipio<input disabled={disabled} maxLength={120} value={form.municipality} onChange={(event) => setForm({ ...form, municipality: event.target.value })} /></label>
    <label className={styles.field}>Zona general<input disabled={disabled} maxLength={160} value={form.area} onChange={(event) => setForm({ ...form, area: event.target.value })} /></label>
    <label className={`${styles.field} ${styles.wide}`}>Relación con Club o campos<textarea disabled={disabled} maxLength={500} value={form.fieldRelationship} onChange={(event) => setForm({ ...form, fieldRelationship: event.target.value })} /></label>
    <label className={`${styles.field} ${styles.wide}`}>Cuéntanos el proyecto<textarea disabled={disabled} maxLength={2000} required value={form.summary} onChange={(event) => setForm({ ...form, summary: event.target.value })} /></label>
  </div>;
}

function ApplicationCard({ application }: { application: OrganizerAccessJson }) {
  return <Link className={styles.application} data-tone={organizerAccessTone(application.status)} href={`/organizacion/solicitudes/${organizerAccessText(application.id)}`}>
    <Status value={application.status} />
    <h3>{organizerAccessText(application.organizerName, "Organización")}</h3>
    <p>{organizerAccessText(organizerAccessRecord(application.plan).name, organizerAccessText(application.requestedPlanCode))}</p>
    <small>{organizerAccessDate(application.updatedAt, true)} · revisión {organizerAccessNumber(application.revision)}</small>
  </Link>;
}

function WorkspaceSummary({ organizer, workspace }: { organizer: OrganizerAccessJson; workspace: OrganizerAccessJson }) {
  const checkpoints = organizerAccessArray(workspace.checkpoints);
  const completed = checkpoints.filter((item) => organizerAccessText(item.status) === "complete").length;
  const percentage = checkpoints.length ? Math.round((completed / checkpoints.length) * 100) : 0;
  return <>
    <Status value={workspace.status} />
    <strong>{organizerAccessText(organizer.name)}</strong>
    <span>{organizerAccessNextActionLabel(workspace.nextAction)}</span>
    <div className={styles.progress} aria-label={`${percentage}% completado`}><span style={{ width: `${percentage}%` }} /></div>
    <small>{completed} de {checkpoints.length} pasos · revisión {organizerAccessNumber(workspace.revision)}</small>
  </>;
}

export function OrganizerAccessClient({ initialApplicationId = "", initialPlanCode = "", surface }: { initialApplicationId?: string; initialPlanCode?: string; surface: Surface }) {
  const [accessToken, setAccessToken] = useState("");
  const [actorId, setActorId] = useState("");
  const [canonical, setCanonical] = useState<OrganizerAccessJson>({});
  const [application, setApplication] = useState<OrganizerAccessJson>({});
  const [selectedOrganizerKey, setSelectedOrganizerKey] = useState("");
  const [selectedPlanCode, setSelectedPlanCode] = useState(initialPlanCode.toUpperCase());
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState("");
  const [form, setForm] = useState<ApplicationForm>(emptyForm);
  const [consent, setConsent] = useState(false);
  const [responseMessage, setResponseMessage] = useState("");
  const [launcherKind, setLauncherKind] = useState<"LEAGUE" | "TOURNAMENT">("LEAGUE");
  const [launcherName, setLauncherName] = useState("");
  const [launcherPreset, setLauncherPreset] = useState("LEAGUE_F7_STANDARD");
  const [launcherModality, setLauncherModality] = useState("FUTBOL_7");
  const [launcherStartsAt, setLauncherStartsAt] = useState("");
  const [launcherEndsAt, setLauncherEndsAt] = useState("");
  const [launcherTeamCount, setLauncherTeamCount] = useState(16);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [online, setOnline] = useState(true);
  const [cached, setCached] = useState(false);
  const [message, setMessage] = useState("");
  const pending = useRef<PendingOperation | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadHome = useCallback(async (token: string, userId: string, allowCache = false) => {
    if (allowCache) {
      const cachedValue = readCache(userId);
      const cachedCanonical = organizerAccessRecord(cachedValue.canonical);
      if (Object.keys(cachedCanonical).length) {
        setCanonical(cachedCanonical);
        setCached(true);
        setLoading(false);
      }
    }
    const response = await fetch("/api/organizer-access/me", { cache: "no-store", headers: bearer(token) });
    const body = await readJson(response);
    const next = organizerAccessRecord(body.canonical);
    setCanonical(next);
    setCached(false);
    setMessage("");
    writeCache(userId, next);
    setLoading(false);
    return next;
  }, []);

  const loadApplication = useCallback(async (token: string, applicationId: string) => {
    if (!applicationId) return;
    const response = await fetch(`/api/organizer-access/application/${encodeURIComponent(applicationId)}`, { cache: "no-store", headers: bearer(token) });
    const body = await readJson(response);
    const next = organizerAccessRecord(body.canonical);
    setApplication(next);
    setForm(formFromApplication(next));
  }, []);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    let removeOnline: (() => void) | undefined;
    const start = async () => {
      setOnline(typeof navigator === "undefined" || navigator.onLine);
      const session = (await supabase?.auth.getSession())?.data.session;
      if (!active) return;
      if (!session) {
        setLoading(false);
        setMessage("Inicia sesión para gestionar el acceso de tus Clubs o equipos.");
        return;
      }
      const token = session.access_token;
      const userId = session.user.id;
      setAccessToken(token);
      setActorId(userId);
      await loadHome(token, userId, true);
      if (initialApplicationId) await loadApplication(token, initialApplicationId);
      const reconcile = () => {
        setOnline(true);
        void loadHome(token, userId).then(() => initialApplicationId ? loadApplication(token, initialApplicationId) : undefined).catch(() => setMessage("No se pudo releer el estado oficial."));
      };
      const onOffline = () => setOnline(false);
      window.addEventListener("online", reconcile);
      window.addEventListener("offline", onOffline);
      removeOnline = () => { window.removeEventListener("online", reconcile); window.removeEventListener("offline", onOffline); };
      if (!supabase) return;
      channel = supabase.channel(`organizer-access:${userId}`)
        .on("postgres_changes", { event: "*", schema: "public", table: organizerAccessRealtimeTable }, () => {
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(reconcile, 120);
        })
        .subscribe((state) => { if (state === "SUBSCRIBED") reconcile(); });
    };
    void start().catch((error) => {
      if (active) { setLoading(false); setMessage(error instanceof Error ? error.message : "No se pudo cargar el área de organización."); }
    });
    return () => {
      active = false;
      removeOnline?.();
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  }, [initialApplicationId, loadApplication, loadHome]);

  const flags = organizerAccessRecord(canonical.flags);
  const organizers = organizerAccessArray(canonical.organizers);
  const plans = organizerAccessArray(canonical.plans);
  const applications = organizerAccessArray(canonical.applications);
  const selectedOrganizer = useMemo(() => {
    const [kind, id] = selectedOrganizerKey.split(":");
    return organizers.find((item) => organizerAccessText(item.kind) === kind && organizerAccessText(item.id) === id) ?? organizers[0] ?? null;
  }, [organizers, selectedOrganizerKey]);
  const eligiblePlans = useMemo(
    () => plans.filter((item) => !selectedOrganizer || organizerAccessText(item.organizerKind) === organizerAccessText(selectedOrganizer.kind)),
    [plans, selectedOrganizer],
  );
  const selectedPlan = eligiblePlans.find((item) => organizerAccessText(item.code) === selectedPlanCode) ?? eligiblePlans[0] ?? null;
  const workspaceEntries = useMemo(() => organizers.flatMap((organizer) => {
    const workspace = organizerAccessRecord(organizer.onboarding);
    return organizerAccessText(workspace.id) ? [{ organizer, workspace }] : [];
  }), [organizers]);
  const selectedWorkspaceEntry = workspaceEntries.find(({ workspace }) => organizerAccessText(workspace.id) === selectedWorkspaceId) ?? workspaceEntries[0] ?? null;
  const selectedWorkspace = selectedWorkspaceEntry?.workspace ?? {};
  const selectedWorkspaceOrganizer = selectedWorkspaceEntry?.organizer ?? {};
  const selectedWorkspaceCheckpoints = organizerAccessArray(selectedWorkspace.checkpoints);

  async function command(action: OrganizerAccessAction, aggregateId: string, expectedRevision: number, payload: OrganizerAccessJson) {
    if (!accessToken || !actorId || !online || cached) {
      setMessage("Sin conexión: puedes consultar la copia local, pero no se guardan operaciones deportivas ni permisos.");
      return null;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    const operationId = operationFor(pending, key);
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:organizer-access-command", "/api/organizer-access/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId, payload }),
        headers: { ...bearer(accessToken), "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await readJson(response);
      const result = organizerAccessRecord(body.canonical);
      const snapshot = organizerAccessRecord(result.snapshot);
      pending.current = null;
      if (organizerAccessText(snapshot.id) && action.startsWith("application.")) {
        setApplication(snapshot);
        setForm(formFromApplication(snapshot));
      }
      setMessage("Cambio confirmado por el servidor.");
      await loadHome(accessToken, actorId);
      if (initialApplicationId) await loadApplication(accessToken, initialApplicationId);
      return snapshot;
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "El estado cambió en otro dispositivo. Se ha recuperado el snapshot oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) {
        await loadHome(accessToken, actorId).catch(() => undefined);
        if (initialApplicationId) await loadApplication(accessToken, initialApplicationId).catch(() => undefined);
      }
      return null;
    } finally {
      setBusy(false);
    }
  }

  async function createApplication(event: FormEvent) {
    event.preventDefault();
    if (!selectedOrganizer || !selectedPlan) return;
    const snapshot = await command("application.create", organizerAccessText(selectedOrganizer.id), 0, {
      ...formPayload(form),
      organizerKind: organizerAccessText(selectedOrganizer.kind),
      planCode: organizerAccessText(selectedPlan.code),
      reason: "organizer_access_application_created",
    });
    const applicationId = organizerAccessText(snapshot?.id);
    if (applicationId) window.location.assign(`/organizacion/solicitudes/${applicationId}`);
  }

  async function saveOrSubmit(action: "application.submit" | "application.update") {
    if (!organizerAccessText(application.id)) return;
    await command(action, organizerAccessText(application.id), organizerAccessNumber(application.revision), {
      ...formPayload(form),
      ...(action === "application.submit" ? { consent } : {}),
      reason: action.replace(".", "_"),
    });
  }

  async function launchFirstCompetition(event: FormEvent) {
    event.preventDefault();
    if (!selectedWorkspaceEntry) return;
    const workspace = selectedWorkspaceEntry.workspace;
    const organizer = selectedWorkspaceEntry.organizer;
    const slug = launcherName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    const payload = launcherKind === "LEAGUE" ? {
      authoringMode: "SIMPLE",
      presetKey: launcherPreset,
    } : {
      authoringMode: "SIMPLE",
      description: "Primera competición creada desde el onboarding de Pachangas IQ.",
      drawMode: "SEEDED_POTS",
      drawTarget: "GROUPS_THEN_KNOCKOUT",
      editionName: `${launcherName} · Edición 1`,
      endsAt: launcherEndsAt,
      generalArea: organizerAccessText(organizer.name),
      groupCount: Math.max(1, Math.min(16, Math.ceil(launcherTeamCount / 4))),
      modality: launcherModality,
      name: launcherName,
      participantCap: launcherTeamCount,
      qualifiersPerGroup: 2,
      registrationClosesAt: launcherStartsAt ? `${launcherStartsAt}T00:00:00.000Z` : "",
      seasonLabel: String(new Date().getFullYear()),
      slug,
      startsAt: launcherStartsAt,
    };
    const snapshot = await command("competition.launch", organizerAccessText(workspace.id), organizerAccessNumber(workspace.revision), {
      launcherKind,
      launcherPayload: payload,
      reason: "first_competition_launcher_confirmed",
    });
    const aggregateId = organizerAccessText(snapshot?.firstLauncherAggregateId);
    if (aggregateId) window.location.assign(launcherKind === "LEAGUE" ? "/ligas" : `/competiciones/${aggregateId}/gestion/participantes`);
  }

  const writeDisabled = busy || !online || cached;
  const shellStatus = cached ? "Copia local" : online ? "Servidor central" : "Sin conexión";
  let body: ReactNode;

  if (loading && !Object.keys(canonical).length) {
    body = <p className={styles.empty}>Consultando el estado oficial...</p>;
  } else if (surface === "apply") {
    body = <>
      {!organizerAccessBoolean(flags.applicationsEnabled) && Object.keys(flags).length ? <p className={styles.empty}>Las solicitudes de organización todavía no están activadas.</p> : null}
      {organizers.length ? <form className={styles.formBand} onSubmit={createApplication}>
        <header className={styles.sectionHeader}><div><span className={styles.eyebrow}>Solicitud privada</span><h2>Cuéntanos qué quieres organizar</h2></div><p>La plataforma revisa la solicitud. Enviar este formulario no concede acceso ni activa una suscripción.</p></header>
        <div className={styles.toolbar}>
          <label className={styles.field}>Organización<select value={selectedOrganizer ? `${organizerAccessText(selectedOrganizer.kind)}:${organizerAccessText(selectedOrganizer.id)}` : ""} onChange={(event) => { setSelectedOrganizerKey(event.target.value); setSelectedPlanCode(""); }}><option value="" disabled>Selecciona</option>{organizers.map((item) => <option key={`${organizerAccessText(item.kind)}:${organizerAccessText(item.id)}`} value={`${organizerAccessText(item.kind)}:${organizerAccessText(item.id)}`}>{organizerAccessText(item.kind) === "CLUB" ? "Club" : "Equipo"} · {organizerAccessText(item.name)}</option>)}</select></label>
          <label className={styles.field}>Plan<select value={selectedPlan ? organizerAccessText(selectedPlan.code) : ""} onChange={(event) => setSelectedPlanCode(event.target.value)}><option value="" disabled>Selecciona</option>{eligiblePlans.map((item) => <option key={organizerAccessText(item.code)} value={organizerAccessText(item.code)}>{organizerAccessText(item.name)}</option>)}</select></label>
          <Status value={selectedOrganizer?.hasCompetitionAccess ? "approved" : "draft"} />
        </div>
        <ApplicationFields disabled={writeDisabled} form={form} setForm={setForm} />
        <div className={styles.actions}><button className={styles.primary} disabled={writeDisabled || !form.summary.trim() || !selectedPlan} type="submit">Guardar borrador</button><Link href="/demo?tab=planes">Ver ejemplo en Mundo Demo</Link></div>
      </form> : <div className={styles.empty}><strong>Necesitas un Club o equipo propio</strong><p>Crea o reclama una organización antes de solicitar acceso.</p><div className={styles.actions}><Link href="/clubes/gestionar">Crear o gestionar Club</Link><Link href="/?mobile=perfil">Gestionar equipo</Link></div></div>}
    </>;
  } else if (surface === "list") {
    body = <section className={styles.sectionBand}><header className={styles.sectionHeader}><div><span className={styles.eyebrow}>Historial privado</span><h2>Solicitudes</h2></div><Link className={styles.secondary} href="/organizacion/solicitar-acceso">Nueva solicitud</Link></header>{applications.length ? <div className={styles.applicationGrid}>{applications.map((item) => <ApplicationCard application={item} key={organizerAccessText(item.id)} />)}</div> : <p className={styles.empty}>Todavía no hay solicitudes.</p>}</section>;
  } else if (surface === "detail") {
    const detail = Object.keys(application).length ? application : applications.find((item) => organizerAccessText(item.id) === initialApplicationId) ?? {};
    const messages = organizerAccessArray(detail.messages);
    const decision = organizerAccessRecord(detail.decision);
    const accessGrant = organizerAccessRecord(detail.accessGrant);
    const onboarding = organizerAccessRecord(detail.onboarding);
    const editable = organizerAccessText(detail.status) === "draft";
    body = Object.keys(detail).length ? <>
      <section className={styles.sectionBand}>
        <header className={styles.sectionHeader}><div><Status value={detail.status} /><h2>{organizerAccessText(detail.organizerName)}</h2></div><p>{organizerAccessText(organizerAccessRecord(detail.plan).name, organizerAccessText(detail.requestedPlanCode))}</p></header>
        <dl className={styles.facts}><div><dt>Proyecto</dt><dd>{organizerAccessText(detail.expectedCompetitionType)}</dd></div><div><dt>Equipos</dt><dd>{detail.expectedTeamCount == null ? "Por decidir" : String(detail.expectedTeamCount)}</dd></div><div><dt>Inicio</dt><dd>{organizerAccessDate(detail.targetStartDate)}</dd></div><div><dt>Revisión</dt><dd>{organizerAccessNumber(detail.revision)}</dd></div></dl>
        {editable ? <><ApplicationFields disabled={writeDisabled} form={form} setForm={setForm} /><label className={styles.checkField}><input checked={consent} disabled={writeDisabled} type="checkbox" onChange={(event) => setConsent(event.target.checked)} /><span>Confirmo que represento a esta organización y autorizo el uso privado de estos datos para revisar el acceso. Solo los verá el equipo autorizado de Pachangas IQ.</span></label><div className={styles.actions}><button className={styles.secondary} disabled={writeDisabled} onClick={() => void saveOrSubmit("application.update")} type="button">Guardar cambios</button><button className={styles.primary} disabled={writeDisabled || !consent || !form.summary.trim()} onClick={() => void saveOrSubmit("application.submit")} type="button">Enviar solicitud</button></div></> : null}
        {organizerAccessText(detail.status) === "needs_information" ? <div className={styles.formGrid}><label className={`${styles.field} ${styles.wide}`}>Respuesta a la plataforma<textarea value={responseMessage} onChange={(event) => setResponseMessage(event.target.value)} /></label><label className={`${styles.checkField} ${styles.wide}`}><input checked={consent} type="checkbox" onChange={(event) => setConsent(event.target.checked)} /><span>Confirmo que la información actualizada es correcta.</span></label><div className={`${styles.actions} ${styles.wide}`}><button className={styles.primary} disabled={writeDisabled || !consent || !responseMessage.trim()} onClick={() => void command("application.respond_information", organizerAccessText(detail.id), organizerAccessNumber(detail.revision), { ...formPayload(form), consent: true, message: responseMessage, reason: "information_response" })} type="button">Enviar respuesta</button></div></div> : null}
        {["draft", "submitted", "under_review", "needs_information"].includes(organizerAccessText(detail.status)) ? <div className={styles.actions}><button className={styles.danger} disabled={writeDisabled} onClick={() => void command("application.withdraw", organizerAccessText(detail.id), organizerAccessNumber(detail.revision), { reason: "withdrawn_by_organizer" })} type="button">Retirar solicitud</button></div> : null}
        {["rejected", "withdrawn", "expired"].includes(organizerAccessText(detail.status)) ? <div className={styles.actions}><button className={styles.secondary} disabled={writeDisabled} onClick={() => void command("application.reconsider", organizerAccessText(detail.id), organizerAccessNumber(detail.revision), { reason: "reconsideration_requested" })} type="button">Solicitar reconsideración</button></div> : null}
      </section>
      {messages.length ? <section className={styles.sectionBand}><header className={styles.sectionHeader}><div><span className={styles.eyebrow}>Conversación</span><h2>Mensajes</h2></div><p>Las notas internas de plataforma no se incluyen en este read model.</p></header><div className={styles.timeline}>{messages.map((item) => <article key={organizerAccessText(item.id)}><header><strong>{organizerAccessText(item.authorKind) === "platform" ? "Pachangas IQ" : "Organización"}</strong><time>{organizerAccessDate(item.createdAt, true)}</time></header><p>{organizerAccessText(item.body)}</p></article>)}</div></section> : null}
      {Object.keys(decision).length ? <section className={styles.decision}><Status value={detail.status} /><strong>{organizerAccessText(decision.message, "Decisión registrada")}</strong><small>{organizerAccessDate(decision.decidedAt, true)} · secuencia {organizerAccessNumber(decision.serverSequence)}</small>{Object.keys(accessGrant).length ? <span>Acceso {organizerAccessStatusLabel(accessGrant.status)} hasta {organizerAccessDate(accessGrant.validUntil)}</span> : <span>Esta decisión no ha creado un grant de suscripción.</span>}{Object.keys(onboarding).length ? <div className={styles.actions}><Link href="/organizacion/onboarding">Continuar onboarding</Link></div> : null}</section> : null}
    </> : <p className={styles.empty}>No se encontró la solicitud o ya no tienes permiso para verla.</p>;
  } else if (surface === "onboarding") {
    body = <>{workspaceEntries.length ? <>
      <section className={styles.sectionBand}>
        <header className={styles.sectionHeader}><div><span className={styles.eyebrow}>Workspace canónico</span><h2>Onboarding de organización</h2></div><p>El progreso se deriva en PostgreSQL del acceso, la competición y sus estados reales.</p></header>
        <div className={styles.workspaceGrid}>{workspaceEntries.map(({ organizer, workspace }) => <button className={styles.application} data-tone={organizerAccessTone(workspace.status)} key={organizerAccessText(workspace.id)} onClick={() => setSelectedWorkspaceId(organizerAccessText(workspace.id))} type="button"><WorkspaceSummary organizer={organizer} workspace={workspace} /></button>)}</div>
      </section>
      {selectedWorkspaceEntry ? <section className={styles.sectionBand}>
        <header className={styles.sectionHeader}><div><span className={styles.eyebrow}>{organizerAccessText(selectedWorkspaceOrganizer.kind)}</span><h2>{organizerAccessText(selectedWorkspaceOrganizer.name)}</h2></div><Status value={selectedWorkspace.status} /></header>
        <div className={styles.checkpoints}>{selectedWorkspaceCheckpoints.map((item) => <div className={styles.checkpoint} data-complete={organizerAccessText(item.status) === "complete"} key={organizerAccessText(item.key)}><b>{organizerAccessText(item.status) === "complete" ? "✓" : "·"}</b><span>{checkpointLabels[organizerAccessText(item.key)] ?? organizerAccessText(item.key)}</span></div>)}</div>
        <div className={styles.actions}>
          <button className={styles.secondary} disabled={writeDisabled} onClick={() => void command("onboarding.refresh", organizerAccessText(selectedWorkspace.id), organizerAccessNumber(selectedWorkspace.revision), { reason: "manual_onboarding_refresh" })} type="button">Actualizar estado</button>
          {organizerAccessText(selectedWorkspace.nextAction) === "CREATE_FIRST_COMPETITION" ? <Link href="/organizacion/empezar">Crear primera competición</Link> : <Link href={organizerAccessText(selectedWorkspace.firstLauncherKind) === "TOURNAMENT" ? "/torneos" : "/ligas"}>{organizerAccessNextActionLabel(selectedWorkspace.nextAction)}</Link>}
          <Link href="/demo?tab=planes">Ver ejemplo completo</Link>
        </div>
      </section> : null}
    </> : <p className={styles.empty}>El onboarding aparecerá cuando exista un grant de organizador vigente.</p>}</>;
  } else {
    const workspace = selectedWorkspace;
    body = workspaceEntries.length ? <form className={styles.formBand} onSubmit={launchFirstCompetition}><header className={styles.sectionHeader}><div><span className={styles.eyebrow}>Primer borrador</span><h2>Crear primera competición</h2></div><p>Confirma los valores iniciales. El servidor crea un único borrador y después abre el wizard canónico.</p></header><div className={styles.toolbar}><label className={styles.field}>Organización<select value={selectedWorkspaceEntry ? organizerAccessText(selectedWorkspaceEntry.workspace.id) : ""} onChange={(event) => setSelectedWorkspaceId(event.target.value)}>{workspaceEntries.map(({ organizer, workspace: item }) => <option value={organizerAccessText(item.id)} key={organizerAccessText(item.id)}>{organizerAccessText(organizer.kind)} · {organizerAccessText(organizer.name)}</option>)}</select></label><span /><Status value={workspace.status} /></div><div className={styles.launcherChoice}><button aria-pressed={launcherKind === "LEAGUE"} onClick={() => setLauncherKind("LEAGUE")} type="button">Liga</button><button aria-pressed={launcherKind === "TOURNAMENT"} onClick={() => setLauncherKind("TOURNAMENT")} type="button">Torneo</button></div>{launcherKind === "LEAGUE" ? <div className={styles.formGrid}><label className={`${styles.field} ${styles.double}`}>Preset<select value={launcherPreset} onChange={(event) => setLauncherPreset(event.target.value)}><option value="LEAGUE_F7_STANDARD">Liga F7 amateur estándar</option><option value="LEAGUE_F5_QUICK">Liga F5 rápida</option><option value="LEAGUE_F11">Liga F11</option><option value="LEAGUE_FUTSAL">Liga de fútbol sala</option></select></label></div> : <div className={styles.formGrid}><label className={`${styles.field} ${styles.double}`}>Nombre<input required maxLength={120} value={launcherName} onChange={(event) => setLauncherName(event.target.value)} /></label><label className={styles.field}>Modalidad<select value={launcherModality} onChange={(event) => setLauncherModality(event.target.value)}><option value="FUTSAL">Fútbol sala</option><option value="FUTBOL_5">Fútbol 5</option><option value="FUTBOL_7">Fútbol 7</option><option value="FUTBOL_11">Fútbol 11</option></select></label><label className={styles.field}>Inicio<input required type="date" value={launcherStartsAt} onChange={(event) => setLauncherStartsAt(event.target.value)} /></label><label className={styles.field}>Fin<input required type="date" value={launcherEndsAt} onChange={(event) => setLauncherEndsAt(event.target.value)} /></label><label className={styles.field}>Máximo de equipos<input min={4} max={64} type="number" value={launcherTeamCount} onChange={(event) => setLauncherTeamCount(Number(event.target.value))} /></label></div>}<div className={styles.actions}><button className={styles.primary} disabled={writeDisabled || !organizerAccessBoolean(flags.firstCompetitionLauncherEnabled) || (launcherKind === "TOURNAMENT" && (!launcherName.trim() || !launcherStartsAt || !launcherEndsAt))} type="submit">Crear borrador en servidor</button><Link href="/demo?tab=planes">Practicar en Mundo Demo</Link></div></form> : <p className={styles.empty}>Necesitas completar una solicitud y disponer de acceso vigente antes de crear la primera competición.</p>;
  }

  return <OfficialProductShellV2 active="perfil" context={{ detail: "Solicitud, revisión y primera competición", eyebrow: "Organización", status: shellStatus, title: "Organizar" }}>
    <main className={styles.page} data-organizer-access-surface={surface}>
      <header className={styles.header}><div><span className={styles.eyebrow}>Organizer Access V1</span><h1>Organiza con Pachangas IQ</h1><p>Solicitud versionada, decisión auditable y acceso confirmado por PostgreSQL.</p></div><Status value={online ? "active" : "draft"} /></header>
      <OrganizerNavigation surface={surface} />
      {message ? <p className={styles.message} data-tone={/confirmado/i.test(message) ? "good" : /conexión|copia/i.test(message) ? "warning" : "danger"} role="status">{message}</p> : null}
      {body}
    </main>
  </OfficialProductShellV2>;
}
