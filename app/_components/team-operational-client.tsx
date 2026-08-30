"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  TEAM_OPERATIONAL_REALTIME_TABLE,
  teamOperationalAppealLabel,
  teamOperationalArray,
  teamOperationalBoolean,
  teamOperationalCacheKey,
  teamOperationalContinuityLabel,
  teamOperationalIsRelevant,
  teamOperationalNextAction,
  teamOperationalNumber,
  teamOperationalRecord,
  teamOperationalScopeLabel,
  teamOperationalStatusLabel,
  teamOperationalText,
  teamOperationalTone,
  type TeamOperationalJson,
  type TeamOperationalOwnerAction,
} from "../team-operational-contract";
import styles from "./team-operational.module.css";

type PendingOperation = { id: string; key: string };

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

async function responseJson(response: Response) {
  const body = teamOperationalRecord(await response.json().catch(() => ({})));
  if (!response.ok) {
    const detail = teamOperationalText(body.message, teamOperationalText(body.error, "Operación no confirmada."));
    if (teamOperationalText(body.error) === "CLIENT_UPDATE_REQUIRED") throw new Error("Actualiza Pachangas IQ antes de guardar cambios.");
    if (/STALE_REVISION|PT409/i.test(detail)) throw new Error("El estado cambió en otro dispositivo. Ya hemos recargado la revisión oficial.");
    throw new Error(detail);
  }
  return body;
}

function cacheRead(actorId: string) {
  try {
    return teamOperationalRecord(JSON.parse(window.localStorage.getItem(teamOperationalCacheKey(actorId)) ?? "null"));
  } catch {
    return {};
  }
}

function cacheWrite(actorId: string, canonical: TeamOperationalJson) {
  try {
    window.localStorage.setItem(teamOperationalCacheKey(actorId), JSON.stringify({ canonical, savedAt: new Date().toISOString() }));
  } catch {
    // This is a disposable read cache and never authorizes a mutation.
  }
}

function operationFor(ref: MutableRefObject<PendingOperation | null>, key: string) {
  if (!ref.current || ref.current.key !== key) ref.current = { id: crypto.randomUUID(), key };
  return ref.current.id;
}

function dateLabel(value: unknown) {
  const raw = teamOperationalText(value);
  if (!raw) return "Sin fecha";
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? "Sin fecha" : new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" }).format(parsed);
}

function Impact({ impact }: { impact: TeamOperationalJson }) {
  const facts: Array<[string, unknown]> = [
    ["Mercado", impact.marketListings],
    ["Retos abiertos", impact.openChallenges],
    ["Competiciones", impact.activeCompetitionEntries],
    ["Solicitudes bloqueadas", impact.blockedOrganizerApplications],
  ];
  return <dl className={styles.impactGrid}>{facts.map(([label, value]) => <div key={String(label)}><dt>{label}</dt><dd>{teamOperationalNumber(value)}</dd></div>)}</dl>;
}

export function TeamOperationalClient({ initialGroupId = "" }: { initialGroupId?: string }) {
  const [accessToken, setAccessToken] = useState("");
  const [actorId, setActorId] = useState("");
  const [canonical, setCanonical] = useState<TeamOperationalJson>({});
  const [selectedId, setSelectedId] = useState(initialGroupId);
  const [appealMessage, setAppealMessage] = useState("");
  const [archiveConfirmed, setArchiveConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [cached, setCached] = useState(false);
  const [loading, setLoading] = useState(true);
  const [online, setOnline] = useState(true);
  const [message, setMessage] = useState("");
  const pending = useRef<PendingOperation | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const teams = useMemo(() => teamOperationalArray(canonical.items), [canonical]);
  const selected = useMemo(() => teams.find((item) => teamOperationalText(item.groupId) === selectedId) ?? teams[0] ?? {}, [selectedId, teams]);
  const selectedGroupId = teamOperationalText(selected.groupId);
  const appeal = teamOperationalRecord(selected.appeal);
  const restrictions = teamOperationalArray(selected.restrictions).filter((item) => teamOperationalText(item.status, "ACTIVE") === "ACTIVE");
  const impact = teamOperationalRecord(selected.impact);
  const isOwner = teamOperationalBoolean(selected.isOwner);

  const load = useCallback(async (token: string, userId: string, allowCache = false) => {
    if (allowCache) {
      const cachedValue = teamOperationalRecord(cacheRead(userId).canonical);
      if (Object.keys(cachedValue).length) {
        setCanonical(cachedValue);
        setCached(true);
        setLoading(false);
      }
    }
    const response = await fetch("/api/team-operational/me", { cache: "no-store", headers: bearer(token) });
    const body = await responseJson(response);
    const next = teamOperationalRecord(body.canonical);
    setCanonical(next);
    setCached(false);
    setLoading(false);
    setMessage("");
    cacheWrite(userId, next);
    return next;
  }, []);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      setOnline(typeof navigator === "undefined" || navigator.onLine);
      const session = (await supabase?.auth.getSession())?.data.session;
      if (!active) return;
      if (!session) {
        setLoading(false);
        setMessage("Inicia sesión para consultar el estado operativo de tus equipos.");
        return;
      }
      const token = session.access_token;
      const userId = session.user.id;
      setAccessToken(token);
      setActorId(userId);
      await load(token, userId, true).catch((error) => {
        setMessage(error instanceof Error ? error.message : "No se pudo cargar el estado oficial.");
        setLoading(false);
      });
      if (!active) return;
      const reconcile = () => {
        setOnline(true);
        void load(token, userId).catch(() => setMessage("No se pudo releer el estado oficial."));
      };
      const onOffline = () => setOnline(false);
      window.addEventListener("online", reconcile);
      window.addEventListener("offline", onOffline);
      document.addEventListener("visibilitychange", reconcile);
      channel = supabase?.channel(`team-operational-${userId}`)
        .on("postgres_changes", { event: "*", schema: "public", table: TEAM_OPERATIONAL_REALTIME_TABLE }, () => {
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(reconcile, 80);
        })
        .subscribe((status) => { if (status === "SUBSCRIBED") reconcile(); }) ?? null;
      return () => {
        window.removeEventListener("online", reconcile);
        window.removeEventListener("offline", onOffline);
        document.removeEventListener("visibilitychange", reconcile);
      };
    };
    let detach: (() => void) | undefined;
    void start().then((value) => { detach = value; });
    return () => {
      active = false;
      detach?.();
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  }, [load]);

  useEffect(() => {
    if (!selectedGroupId || typeof window === "undefined") return;
    const url = new URL(window.location.href);
    url.searchParams.set("grupo", selectedGroupId);
    window.history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
  }, [selectedGroupId]);

  const mutate = useCallback(async (action: TeamOperationalOwnerAction, payload: TeamOperationalJson, key: string) => {
    if (!accessToken || !actorId || !selectedGroupId || busy) return;
    if (!online) {
      setMessage("Sin conexión: puedes leer la última copia, pero no guardar acciones del equipo.");
      return;
    }
    setBusy(true);
    setMessage("");
    const operationId = operationFor(pending, key);
    try {
      const response = await clientWriteFetch("api:team-operational-command", "/api/team-operational/state", {
        body: JSON.stringify({ action, expectedRevision: teamOperationalNumber(selected.revision), groupId: selectedGroupId, operationId, payload }),
        cache: "no-store",
        headers: { ...bearer(accessToken), "Content-Type": "application/json" },
        method: "POST",
      });
      await responseJson(response);
      pending.current = null;
      setAppealMessage("");
      setArchiveConfirmed(false);
      await load(accessToken, actorId);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "La operación no quedó confirmada.");
      await load(accessToken, actorId).catch(() => undefined);
    } finally {
      setBusy(false);
    }
  }, [accessToken, actorId, busy, load, online, selected.revision, selectedGroupId]);

  if (loading && !teams.length) return <main className={styles.page}><p className={styles.sync}>Recuperando el estado confirmado por PostgreSQL...</p></main>;
  if (!teams.length) return <main className={styles.page}><header className={styles.header}><div><span className={styles.eyebrow}>Equipo</span><h1>Estado del equipo</h1><p>{message || "Todavía no perteneces a ningún equipo."}</p></div></header></main>;

  const effectiveStatus = teamOperationalText(selected.effectiveStatus, "ACTIVE");
  const appealStatus = teamOperationalText(appeal.status);
  const canCreateAppeal = isOwner && ["LIMITED", "SUSPENDED"].includes(teamOperationalText(selected.enforcement))
    && !["DRAFT", "SUBMITTED", "UNDER_REVIEW"].includes(appealStatus);

  return <main className={styles.page}>
    <header className={styles.header}>
      <div><span className={styles.eyebrow}>Autoridad del equipo</span><h1>Estado del equipo</h1><p>Consulta disponibilidad, restricciones y continuidad. Solo el servidor confirma cualquier cambio.</p></div>
      <label className={styles.selector}>Equipo<select value={selectedGroupId} onChange={(event) => setSelectedId(event.target.value)}>{teams.map((team) => <option key={teamOperationalText(team.groupId)} value={teamOperationalText(team.groupId)}>{teamOperationalText(team.teamName, "Equipo")}</option>)}</select></label>
    </header>
    <div className={styles.sync} data-online={online ? "true" : "false"}><span>{online ? cached ? "Copia local revalidándose" : "Snapshot canónico" : "Sin conexión · copia local de lectura"}</span><span>Revisión {teamOperationalNumber(selected.revision)} · secuencia {teamOperationalNumber(selected.serverSequence)}</span></div>
    {message ? <p className={styles.message} role="status">{message}</p> : null}
    <section className={styles.statusBand}>
      <div className={styles.statusLead} data-tone={teamOperationalTone(effectiveStatus)}><span>{teamOperationalStatusLabel(effectiveStatus)}</span><h2>{teamOperationalText(selected.teamName, "Equipo")}</h2><p>{teamOperationalText(selected.publicMessage, "El equipo puede utilizar todas las funciones disponibles.")}</p><small>{teamOperationalNextAction(selected)}</small></div>
      <dl className={styles.statusFacts}>
        <div><dt>Ciclo de vida</dt><dd>{teamOperationalStatusLabel(selected.lifecycle)}</dd></div>
        <div><dt>Plataforma</dt><dd>{teamOperationalStatusLabel(selected.enforcement)}</dd></div>
        <div><dt>Continuidad</dt><dd>{teamOperationalContinuityLabel(selected.continuityPolicy)}</dd></div>
        <div><dt>Vigencia</dt><dd>{selected.effectiveUntil ? dateLabel(selected.effectiveUntil) : "Sin caducidad"}</dd></div>
      </dl>
    </section>
    <div className={styles.columns}>
      <div className={styles.ownerActions}>
        <section className={styles.section}>
          <header className={styles.sectionHeader}><div><span>Impacto</span><h2>Ámbitos y continuidad</h2></div><small>{restrictions.length} restricción{restrictions.length === 1 ? "" : "es"} activa{restrictions.length === 1 ? "" : "s"}</small></header>
          {restrictions.length ? <div className={styles.restrictionList}>{restrictions.map((restriction, index) => <article className={styles.restriction} key={`${teamOperationalText(restriction.scope)}-${index}`}><strong>{teamOperationalScopeLabel(restriction.scope)}</strong><span>{teamOperationalText(restriction.publicMessage, teamOperationalText(selected.publicMessage))}</span><small>{restriction.effectiveUntil ? `Hasta ${dateLabel(restriction.effectiveUntil)}` : "Sin caducidad"}</small></article>)}</div> : <p className={styles.empty}>No hay restricciones activas.</p>}
          {isOwner ? <Impact impact={impact} /> : <p className={styles.empty}>El detalle de impacto operativo solo está disponible para el owner.</p>}
        </section>
        <section className={styles.section}>
          <header className={styles.sectionHeader}><div><span>Revisión</span><h2>Apelación</h2></div><small>{appealStatus ? teamOperationalAppealLabel(appealStatus) : "Sin solicitud"}</small></header>
          {appealStatus ? <div className={styles.appeal}><strong>{teamOperationalAppealLabel(appealStatus)}</strong>{teamOperationalText(appeal.ownerMessage) ? <p>{teamOperationalText(appeal.ownerMessage)}</p> : null}{teamOperationalText(appeal.safeResolutionMessage) ? <p>{teamOperationalText(appeal.safeResolutionMessage)}</p> : null}<small>Revisión de apelación {teamOperationalNumber(appeal.revision)}{appeal.deadlineAt ? ` · respuesta prevista ${dateLabel(appeal.deadlineAt)}` : ""}</small></div> : <p className={styles.empty}>No existe una apelación abierta.</p>}
        </section>
      </div>
      <section className={styles.section}>
        <header className={styles.sectionHeader}><div><span>Owner</span><h2>Acciones disponibles</h2></div><small>{isOwner ? "Confirmación central" : "Solo lectura"}</small></header>
        {!isOwner ? <p className={styles.empty}>Solo el owner puede archivar, restaurar o solicitar una revisión. Admins y miembros conservan acceso de lectura.</p> : <div className={styles.ownerActions}>
          {canCreateAppeal ? <div className={styles.actionBlock}><h3>Solicitar revisión</h3><p>Explica el motivo con información verificable. La solicitud no retira automáticamente la medida.</p><label className={styles.field}>Mensaje<textarea maxLength={3000} value={appealMessage} onChange={(event) => setAppealMessage(event.target.value)} /></label><div className={styles.actions}><button className={styles.primary} disabled={busy || appealMessage.trim().length < 10} type="button" onClick={() => void mutate("team.appeal.create", { message: appealMessage, reasonCode: "owner.review.requested", requestedOutcome: "REVIEW" }, `appeal-create:${selectedGroupId}:${teamOperationalNumber(selected.revision)}`)}>Preparar solicitud</button></div></div> : null}
          {appealStatus === "DRAFT" ? <div className={styles.actionBlock}><h3>Enviar apelación</h3><p>Al enviarla, la plataforma recibirá el aviso obligatorio.</p><div className={styles.actions}><button className={styles.primary} disabled={busy} type="button" onClick={() => void mutate("team.appeal.submit", { appealId: teamOperationalText(appeal.id), message: appealMessage || teamOperationalText(appeal.ownerMessage), reasonCode: "owner.appeal.submitted" }, `appeal-submit:${teamOperationalText(appeal.id)}:${teamOperationalNumber(selected.revision)}`)}>Enviar</button><button className={styles.secondary} disabled={busy} type="button" onClick={() => void mutate("team.appeal.withdraw", { appealId: teamOperationalText(appeal.id), reasonCode: "owner.appeal.withdrawn" }, `appeal-withdraw:${teamOperationalText(appeal.id)}:${teamOperationalNumber(selected.revision)}`)}>Descartar</button></div></div> : null}
          {["SUBMITTED", "UNDER_REVIEW"].includes(appealStatus) ? <div className={styles.actionBlock}><h3>Solicitud enviada</h3><p>Puedes retirarla mientras no haya una resolución terminal.</p><div className={styles.actions}><button className={styles.secondary} disabled={busy} type="button" onClick={() => void mutate("team.appeal.withdraw", { appealId: teamOperationalText(appeal.id), reasonCode: "owner.appeal.withdrawn" }, `appeal-withdraw:${teamOperationalText(appeal.id)}:${teamOperationalNumber(selected.revision)}`)}>Retirar solicitud</button></div></div> : null}
          {teamOperationalText(selected.lifecycle) === "ACTIVE" ? <div className={styles.actionBlock}><h3>Archivar equipo</h3><p>Oculta la actividad nueva sin borrar el histórico deportivo. No puede usarse para retirar una medida de plataforma.</p><label className={styles.confirm}><input checked={archiveConfirmed} onChange={(event) => setArchiveConfirmed(event.target.checked)} type="checkbox" />Confirmo que quiero archivar voluntariamente el equipo.</label><div className={styles.actions}><button className={styles.danger} disabled={busy || !archiveConfirmed || ["LIMITED", "SUSPENDED"].includes(teamOperationalText(selected.enforcement))} type="button" onClick={() => void mutate("team.lifecycle.archive", { confirm: true, continuityPolicy: "HISTORY_ONLY", reasonCode: "owner.voluntary.archive" }, `archive:${selectedGroupId}:${teamOperationalNumber(selected.revision)}`)}>Archivar</button></div></div> : <div className={styles.actionBlock}><h3>Restaurar equipo</h3><p>Reactiva el ciclo de vida. Las decisiones de plataforma siguen siendo independientes.</p><div className={styles.actions}><button className={styles.primary} disabled={busy} type="button" onClick={() => void mutate("team.lifecycle.restore", { confirm: true, reasonCode: "owner.lifecycle.restore" }, `restore-lifecycle:${selectedGroupId}:${teamOperationalNumber(selected.revision)}`)}>Restaurar</button></div></div>}
        </div>}
      </section>
    </div>
    <Link href="/?mobile=perfil">Volver al perfil</Link>
  </main>;
}

export function TeamOperationalHomeCard({ groupId }: { groupId: string }) {
  const [snapshot, setSnapshot] = useState<TeamOperationalJson>({});

  useEffect(() => {
    if (!groupId) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    let accessToken = "";
    let actorId = "";
    const load = async () => {
      if (!accessToken || !actorId || !active) return;
      const cached = teamOperationalRecord(cacheRead(actorId).canonical);
      const cachedTeam = teamOperationalArray(cached.items).find((item) => teamOperationalText(item.groupId) === groupId);
      if (cachedTeam) setSnapshot(cachedTeam);
      if (!navigator.onLine) return;
      const response = await fetch(`/api/team-operational/state?groupId=${encodeURIComponent(groupId)}`, { cache: "no-store", headers: bearer(accessToken) });
      const body = await responseJson(response);
      if (active) setSnapshot(teamOperationalRecord(body.canonical));
    };
    const start = async () => {
      const session = (await supabase?.auth.getSession())?.data.session;
      if (!session || !active) return;
      accessToken = session.access_token;
      actorId = session.user.id;
      const cached = teamOperationalRecord(cacheRead(session.user.id).canonical);
      const cachedTeam = teamOperationalArray(cached.items).find((item) => teamOperationalText(item.groupId) === groupId);
      if (cachedTeam) setSnapshot(cachedTeam);
      await load();
      channel = supabase?.channel(`team-operational-home-${groupId}`)
        .on("postgres_changes", { event: "*", filter: `group_id=eq.${groupId}`, schema: "public", table: TEAM_OPERATIONAL_REALTIME_TABLE }, () => { void load(); })
        .subscribe((status) => { if (status === "SUBSCRIBED") void load(); }) ?? null;
    };
    void start().catch(() => undefined);
    return () => { active = false; if (channel && supabase) void supabase.removeChannel(channel); };
  }, [groupId]);

  if (!teamOperationalIsRelevant(snapshot)) return null;
  const status = teamOperationalText(snapshot.effectiveStatus);
  return <Link className={styles.homeNotice} data-tone={teamOperationalTone(status)} href={`/equipo/estado?grupo=${encodeURIComponent(groupId)}`}><span>Estado del equipo</span><strong>{teamOperationalStatusLabel(status)}</strong><small>{teamOperationalNextAction(snapshot)}</small></Link>;
}
