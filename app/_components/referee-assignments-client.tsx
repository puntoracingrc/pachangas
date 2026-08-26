"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import {
  refereeAssignmentActions,
  refereeAssignmentArray,
  refereeAssignmentDate,
  refereeAssignmentRevision,
  refereeAssignmentStatusLabel,
  refereeAssignmentTitle,
  refereeAssignmentTone,
  refereeFeeLabel,
  refereePrivateTerms,
  refereeScheduleStateLabel,
} from "../referee-assignment-contract";
import { clientWriteFetch } from "../pwa-client-bridge";
import { refereeArray, refereeNumber, refereeRecord, refereeText, type RefereeJson } from "../referee-platform-contract";
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
import styles from "./referee-assignments-client.module.css";

export type RefereeAssignmentSurface = "club" | "competition" | "match" | "my";

type PlayerOption = { id: string; label: string };

type Props = {
  canonicalMatchId?: string;
  clubId?: string;
  competitionId?: string;
  competitionMatchContextId?: string;
  embedded?: boolean;
  playerOptions?: PlayerOption[];
  previewData?: RefereeJson | null;
  surface: RefereeAssignmentSurface;
};

const cacheVersion = 1;

function endpointFor(props: Props) {
  if (props.surface === "competition") return `/api/referee-assignments/competition/${props.competitionId ?? ""}`;
  if (props.surface === "match") return `/api/referee-assignments/match/${props.canonicalMatchId ?? ""}`;
  if (props.surface === "club") return `/api/referee-assignments/club/${props.clubId ?? ""}`;
  return "/api/referee-assignments/me";
}

function scopeId(props: Props) {
  return props.canonicalMatchId || props.competitionId || props.clubId || "my";
}

function cacheKey(surface: RefereeAssignmentSurface, identity: string, userId: string) {
  return `pachangas-referee-assignment-read-v1:${surface}:${identity}:${userId}`;
}

function cacheLifetime(data: RefereeJson) {
  const items = collectAssignments(data);
  const terminal = items.length > 0 && items.every((item) => ["cancelled", "completed", "declined", "expired", "replaced"].includes(refereeText(item.status)));
  return terminal ? 7 * 24 * 60 * 60 * 1000 : 3 * 60 * 1000;
}

function readCache(key: string) {
  try {
    const envelope = refereeRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (refereeNumber(envelope.version) !== cacheVersion || Date.now() > refereeNumber(envelope.expiresAt)) return null;
    return refereeRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, data: RefereeJson) {
  try {
    window.localStorage.setItem(key, JSON.stringify({
      data,
      expiresAt: Date.now() + cacheLifetime(data),
      storedAt: new Date().toISOString(),
      version: cacheVersion,
    }));
  } catch {
    // Optional read cache. It never authorizes or confirms a sport operation.
  }
}

function collectAssignments(data: RefereeJson | null): RefereeJson[] {
  if (!data) return [];
  const direct = refereeAssignmentArray(data.items);
  if (direct.length) return direct;
  return refereeArray(data.matches).flatMap((match) => refereeAssignmentArray(match.assignments).map((assignment): RefereeJson => ({
    ...assignment,
    deskMatch: match,
  })));
}

function feedbackTone(message: string): "danger" | "info" | "success" | "warning" {
  if (/confirmad|actualizad|guardad/i.test(message)) return "success";
  if (/conflict|cambi|obsolet|recarga|pendiente/i.test(message)) return "warning";
  if (/no |error|rechaz|requiere|cerrad/i.test(message)) return "danger";
  return "info";
}

function userMessage(detail: string) {
  if (/STALE_REVISION|STALE_SCHEDULE|MATCH_SCHEDULE_CHANGED/i.test(detail)) return "El partido cambió. Hemos recuperado la revisión oficial antes de continuar.";
  if (/TIME_CONFLICT/i.test(detail)) return "El árbitro ya tiene otro partido que se solapa con este horario.";
  if (/SLOT_TAKEN/i.test(detail)) return "El puesto de árbitro principal ya está ocupado.";
  if (/PROFILE_NOT_ASSIGNABLE/i.test(detail)) return "La ficha arbitral ya no está disponible para este partido.";
  if (/AUTHENTICATION_REQUIRED/i.test(detail)) return "Inicia sesión para consultar esta asignación.";
  return detail;
}

function assignmentCapabilities(surface: RefereeAssignmentSurface, data: RefereeJson) {
  const root = refereeRecord(data.capabilities);
  return {
    refereeOwner: surface === "my",
    requesterManage: surface === "competition" || (surface === "club" && root.manage === true) || (surface === "match" && root.manage === true),
  };
}

function marketHref(assignment: RefereeJson, replacement = false) {
  const query = new URLSearchParams({ tab: "arbitros" });
  query.set("partido", refereeText(assignment.sourceId));
  query.set("titulo", refereeAssignmentTitle(assignment));
  query.set("sourceKind", refereeText(assignment.sourceKind));
  query.set("requesterKind", refereeText(assignment.requesterKind));
  query.set("requesterId", refereeText(assignment.requesterTeamId) || refereeText(assignment.requesterClubId) || refereeText(assignment.requesterCompetitionId));
  if (refereeText(assignment.sourceGroupId)) query.set("grupoId", refereeText(assignment.sourceGroupId));
  if (refereeText(assignment.competitionId)) query.set("competitionId", refereeText(assignment.competitionId));
  if (refereeText(assignment.canonicalMatchId)) query.set("canonicalMatchId", refereeText(assignment.canonicalMatchId));
  if (refereeText(assignment.competitionMatchContextId)) query.set("competitionMatchContextId", refereeText(assignment.competitionMatchContextId));
  if (replacement) {
    query.set("replaceAssignment", refereeText(assignment.id));
    query.set("replaceRevision", String(refereeAssignmentRevision(assignment)));
  }
  return `/mercado?${query.toString()}`;
}

function unassignedMarketHref(match: RefereeJson, competitionId: string) {
  const query = new URLSearchParams({
    canonicalMatchId: refereeText(match.canonicalMatchId),
    competitionId,
    competitionMatchContextId: refereeText(match.competitionMatchContextId),
    partido: refereeText(match.competitionMatchContextId),
    requesterId: competitionId,
    requesterKind: "COMPETITION",
    sourceKind: "competition_generated",
    tab: "arbitros",
    titulo: "Partido de competición",
  });
  return `/mercado?${query.toString()}`;
}

function actionLabel(action: string) {
  return ({
    "assignment.accept": "Aceptar",
    "assignment.cancel": "Cancelar",
    "assignment.confirm": "Confirmar",
    "assignment.decline": "Rechazar",
    "assignment.reconfirm": "Aceptar nuevo horario",
    "terms.accept": "Aceptar contraoferta",
    "terms.decline": "Rechazar contraoferta",
  } as Record<string, string>)[action] ?? action;
}

export function RefereeAssignmentsClient(props: Props) {
  const { embedded = false, playerOptions = [], previewData = null, surface } = props;
  const endpoint = endpointFor(props);
  const identity = scopeId(props);
  const [data, setData] = useState<RefereeJson | null>(previewData);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(previewData ? "Escenario visual aislado" : "");
  const [counterEuros, setCounterEuros] = useState<Record<string, string>>({});
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (token: string, actorId: string, reason: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch(endpoint, { cache: "no-store", headers: { Authorization: `Bearer ${token}` } });
      const body = refereeRecord(await response.json());
      if (!response.ok) throw new Error(refereeText(body.message) || "No se pudo recuperar la asignación canónica.");
      setData(body);
      setCached(false);
      writeCache(cacheKey(surface, identity, actorId), body);
      if (reason === "realtime") setMessage("Asignaciones actualizadas desde PostgreSQL.");
    } catch (error) {
      setMessage(userMessage(error instanceof Error ? error.message : "No se pudo recuperar la asignación canónica."));
    } finally {
      setLoading(false);
    }
  }, [endpoint, identity, surface]);

  useEffect(() => {
    if (previewData) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    let removeOnline: (() => void) | undefined;
    void supabase?.auth.getSession().then(({ data: sessionData }) => {
      if (!active) return;
      const token = sessionData.session?.access_token ?? "";
      const actorId = sessionData.session?.user.id ?? "";
      if (!token || !actorId) {
        setLoading(false);
        setMessage("Inicia sesión para consultar las asignaciones arbitrales.");
        return;
      }
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(cacheKey(surface, identity, actorId));
      if (local) { setData(local); setCached(true); setLoading(false); }
      void loadCanonical(token, actorId, "initial");
      const reconcile = (delay = 120) => {
        if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
        realtimeTimer.current = window.setTimeout(() => {
          if (active) void loadCanonical(token, actorId, "realtime");
        }, delay);
      };
      channel = supabase?.channel(`referee-assignments:${surface}:${identity}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_referee_invalidations" }, (payload) => {
          const row = refereeRecord(refereeRecord(payload).new);
          if (["referee_assignment", "referee_foundation_flags", "referee_statistics"].includes(refereeText(row.entity_type))) reconcile();
        })
        .subscribe((status) => { if (status === "SUBSCRIBED") reconcile(400); }) ?? null;
      const online = () => reconcile(0);
      window.addEventListener("online", online);
      removeOnline = () => window.removeEventListener("online", online);
    });
    return () => {
      active = false;
      removeOnline?.();
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  }, [identity, loadCanonical, previewData, surface]);

  const run = useCallback(async (action: string, assignment: RefereeJson, payload: RefereeJson = {}) => {
    if (previewData) { setMessage("Escenario visual: no se ha enviado ninguna escritura."); return; }
    if (!accessToken) { setMessage("Inicia sesión para continuar."); return; }
    const aggregateId = refereeText(assignment.id);
    const expectedRevision = refereeAssignmentRevision(assignment);
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    const officiating = action === "result.observe" || action === "discipline.record";
    try {
      const response = await clientWriteFetch(
        officiating ? "api:referee-officiating-command" : "api:referee-assignment-command",
        officiating ? "/api/referee-assignments/officiating" : "/api/referee-assignments/command",
        {
          body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          method: "POST",
        },
      );
      const body = refereeRecord(await response.json());
      if (!response.ok) throw new Error(refereeText(body.message) || "Operación no confirmada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await loadCanonical(accessToken, userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(userMessage(detail));
      if (/STALE_REVISION|STALE_SCHEDULE|MATCH_SCHEDULE_CHANGED/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
    } finally {
      setBusy(false);
    }
  }, [accessToken, loadCanonical, previewData, userId]);

  const assignments = useMemo(() => collectAssignments(data), [data]);
  const capabilities = assignmentCapabilities(surface, data ?? {});
  const summary = refereeRecord(data?.summary);
  const matches = refereeArray(data?.matches);
  const unassigned = surface === "competition"
    ? matches.filter((match) => !refereeAssignmentArray(match.assignments).some((item) => ["accepted", "confirmed", "completed"].includes(refereeText(item.status))))
    : [];

  function counter(event: FormEvent<HTMLFormElement>, assignment: RefereeJson) {
    event.preventDefault();
    const euros = Number(counterEuros[refereeText(assignment.id)]);
    if (!Number.isFinite(euros) || euros < 0) { setMessage("Indica una contraoferta válida."); return; }
    void run("terms.counter", assignment, { counterFeeCents: Math.round(euros * 100), reason: "referee_terms_counter" });
  }

  function observe(event: FormEvent<HTMLFormElement>, assignment: RefereeJson) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void run("result.observe", assignment, {
      awayScore: Number(form.get("awayScore")),
      homeScore: Number(form.get("homeScore")),
      privateNote: String(form.get("privateNote") ?? "").trim(),
    });
  }

  function discipline(event: FormEvent<HTMLFormElement>, assignment: RefereeJson) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void run("discipline.record", assignment, {
      cardTypeCode: String(form.get("cardTypeCode") ?? ""),
      context: "in_match",
      evidenceRefs: [],
      minute: Number(form.get("minute")),
      period: String(form.get("period") ?? ""),
      playerProfileId: String(form.get("playerProfileId") ?? ""),
      privateNotes: String(form.get("privateNotes") ?? "").trim(),
      publicReasonCategory: String(form.get("publicReasonCategory") ?? "").trim(),
      publicSummary: String(form.get("publicSummary") ?? "").trim(),
    });
  }

  const title = surface === "my" ? "Mis asignaciones arbitrales" : surface === "competition" ? "Mesa arbitral" : surface === "club" ? "Arbitraje del Club" : "Árbitro del partido";
  const content = <main className={styles.page} data-referee-assignment-surface={surface}>
    {!embedded ? <GamePageHeader eyebrow="Referee Assignments · Beta privada" title={title} /> : <SectionHeader eyebrow="Árbitro principal" title={title} />}
    {message ? <ProductFeedback tone={feedbackTone(message)}>{message}</ProductFeedback> : null}
    {cached ? <ProductFeedback tone="warning">Copia local visible mientras se verifica el snapshot oficial.</ProductFeedback> : null}
    {loading && !data ? <p className={styles.empty}>Recuperando asignaciones canónicas...</p> : null}
    {data && surface !== "match" ? <section className={styles.metrics} aria-label="Resumen arbitral">
      <MetricTile label="Pendientes" value={refereeNumber(summary.pending ?? summary.proposed)} />
      <MetricTile label="Aceptadas" value={refereeNumber(summary.accepted)} />
      <MetricTile label="Confirmadas" value={refereeNumber(summary.confirmed)} />
      <MetricTile label="Reconfirmar" value={refereeNumber(summary.reconfirmationRequired)} />
      <MetricTile label="Completadas" value={refereeNumber(summary.completed)} />
    </section> : null}
    {unassigned.length ? <section className={styles.unassigned}><SectionHeader eyebrow="Sin árbitro principal" title="Partidos por cubrir" /><div>{unassigned.map((match) => <article key={refereeText(match.competitionMatchContextId)}><span><strong>{refereeText(match.venueLabel) || "Sede pendiente"}</strong><small>{refereeAssignmentDate(match)}</small></span><Link href={unassignedMarketHref(match, props.competitionId ?? "")}>Buscar árbitro</Link></article>)}</div></section> : null}
    {surface === "match" && !loading && !assignments.length && capabilities.requesterManage && props.competitionId && props.competitionMatchContextId ? <section className={styles.unassigned}><SectionHeader eyebrow="Puesto libre" title="Árbitro principal" /><div><article><span><strong>Sin asignación confirmada</strong><small>La propuesta se crea desde el Mercado arbitral.</small></span><Link href={unassignedMarketHref({ canonicalMatchId: props.canonicalMatchId, competitionMatchContextId: props.competitionMatchContextId }, props.competitionId)}>Buscar árbitro</Link></article></div></section> : null}
    <section className={styles.assignmentList} aria-label="Asignaciones arbitrales">
      {assignments.map((assignment) => {
        const referee = refereeRecord(assignment.referee);
        const terms = refereePrivateTerms(assignment);
        const actions = refereeAssignmentActions(assignment, capabilities);
        const assignmentId = refereeText(assignment.id);
        return <article className={styles.assignmentCard} key={assignmentId}>
          <header>
            <div><span>{refereeText(assignment.competitionName) || refereeText(assignment.requesterName) || "Partido"}</span><h3>{refereeAssignmentTitle(assignment)}</h3><small>{refereeAssignmentDate(assignment)}</small></div>
            <div className={styles.chips}><StatusChip tone={refereeAssignmentTone(assignment.status)}>{refereeAssignmentStatusLabel(assignment.status)}</StatusChip><StatusChip tone={refereeText(assignment.scheduleState) === "CURRENT" ? "success" : "warning"}>{refereeScheduleStateLabel(assignment.scheduleState)}</StatusChip></div>
          </header>
          <div className={styles.facts}>
            <span><b>Árbitro</b>{refereeText(referee.displayName) || "Ficha arbitral"}</span>
            <span><b>Campo</b>{refereeText(assignment.venueLabel) || "Pendiente"}</span>
            <span><b>Modalidad</b>{refereeText(assignment.modality).replaceAll("_", " ") || "Partido"}</span>
            {Object.keys(terms).length ? <span><b>Acuerdo privado</b>{refereeFeeLabel(assignment)} · {refereeText(terms.status).replaceAll("_", " ")}</span> : null}
          </div>
          <ResponsiveActionBar className={styles.actions}>
            {actions.filter((action) => !["assignment.replace", "discipline.record", "result.observe", "terms.counter"].includes(action)).map((action) => <button disabled={busy} key={action} onClick={() => void run(action, assignment, { reason: `referee_ui_${action.replaceAll(".", "_")}`, reasonCode: "user_action", reasonText: "Acción confirmada desde Referee Assignments" })} type="button">{actionLabel(action)}</button>)}
            {actions.includes("assignment.replace") ? <Link href={marketHref(assignment, true)}>Buscar sustituto</Link> : null}
          </ResponsiveActionBar>
          {actions.includes("terms.counter") ? <form className={styles.inlineForm} onSubmit={(event) => counter(event, assignment)}><label>Contraoferta (€)<input inputMode="decimal" min="0" onChange={(event) => setCounterEuros((current) => ({ ...current, [assignmentId]: event.target.value }))} step="0.50" type="number" value={counterEuros[assignmentId] ?? ""} /></label><button disabled={busy} type="submit">Enviar contraoferta</button></form> : null}
          {actions.includes("result.observe") ? <details className={styles.officiating}><summary>Acta privada</summary><form onSubmit={(event) => observe(event, assignment)}><label>Local<input max="99" min="0" name="homeScore" required type="number" /></label><label>Visitante<input max="99" min="0" name="awayScore" required type="number" /></label><label className={styles.wide}>Nota privada<textarea maxLength={1200} name="privateNote" rows={2} /></label><button disabled={busy} type="submit">Guardar observación</button></form>{playerOptions.length ? <form onSubmit={(event) => discipline(event, assignment)}><label>Jugador<select name="playerProfileId" required>{playerOptions.map((player) => <option key={player.id} value={player.id}>{player.label}</option>)}</select></label><label>Tarjeta<select name="cardTypeCode"><option value="YELLOW">Amarilla</option><option value="RED">Roja</option><option value="BLUE">Azul</option></select></label><label>Minuto<input max="300" min="0" name="minute" required type="number" /></label><label>Periodo<input defaultValue="REGULATION" name="period" /></label><label>Motivo<input maxLength={120} name="publicReasonCategory" required /></label><label className={styles.wide}>Resumen público<input maxLength={500} name="publicSummary" required /></label><label className={styles.wide}>Notas privadas<textarea maxLength={4000} name="privateNotes" rows={2} /></label><button disabled={busy} type="submit">Registrar tarjeta R5</button></form> : null}<p>Esta acta aporta evidencia. No decide el resultado oficial ni las sanciones.</p></details> : null}
        </article>;
      })}
      {!loading && !assignments.length ? <p className={styles.empty}>No hay asignaciones en este contexto.</p> : null}
    </section>
  </main>;

  if (embedded) return content;
  return <OfficialProductShellV2 active={surface === "my" || surface === "club" ? "perfil" : "partido"} context={{ detail: cached ? "Caché en revalidación" : "Snapshot canónico", eyebrow: "Beta privada", status: loading ? "Sincronizando" : "Servidor", title }}>{content}</OfficialProductShellV2>;
}
