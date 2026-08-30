"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import {
  readSeasonVenueCache,
  seasonVenueMode,
  seasonVenueStatus,
  venueArray,
  venueNumber,
  venueRecord,
  venueText,
  writeSeasonVenueCache,
  type SeasonVenueSurface,
  type VenueJson,
} from "../season-venue-allocation-contract";
import { supabase } from "../supabaseClient";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import styles from "./season-venue-planner.module.css";

type Props = {
  competitionId?: string;
  seriesId?: string;
  surface: SeasonVenueSurface;
};

type Pane = "matches" | "fields" | "assignment" | "conflicts" | "summary";

function formText(form: FormData, name: string) {
  return String(form.get(name) ?? "").trim();
}

function query(input: Record<string, string | null | undefined>) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(input)) if (value) params.set(key, value);
  return params.toString();
}

function Metric({ label, value }: { label: string; value: unknown }) {
  return <div className={styles.metric}><span>{label}</span><strong>{venueNumber(value)}</strong></div>;
}

function StatusChip({ value }: { value: unknown }) {
  return <span className={styles.chip}>{seasonVenueStatus(value)}</span>;
}

export function SeasonVenuePlannerClient({ competitionId = "", seriesId = "", surface }: Props) {
  const [accessToken, setAccessToken] = useState("");
  const [actorId, setActorId] = useState("");
  const [clubId, setClubId] = useState("");
  const [data, setData] = useState<VenueJson | null>(null);
  const [selectedPlanId, setSelectedPlanId] = useState("");
  const [selectedPoolId, setSelectedPoolId] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [online, setOnline] = useState(() => typeof navigator === "undefined" ? true : navigator.onLine);
  const [message, setMessage] = useState(supabase ? "" : "Supabase no está configurado.");
  const [pane, setPane] = useState<Pane>("assignment");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const reconcileRef = useRef<(() => Promise<void>) | null>(null);

  const cacheScope = useMemo(() => [surface, competitionId, seriesId, clubId, selectedPlanId].join(":"), [clubId, competitionId, selectedPlanId, seriesId, surface]);

  const read = useCallback(async (params: Record<string, string | null | undefined>, token: string) => {
    const response = await fetch("/api/season-venues/read?" + query(params), {
      cache: "no-store",
      headers: { Authorization: "Bearer " + token },
    });
    const body = await response.json() as VenueJson;
    if (!response.ok) throw new Error(venueText(body.message) || "No se pudo recuperar el estado canónico.");
    return body;
  }, []);

  const load = useCallback(async (token: string, targetClubId = clubId, reason: "initial" | "manual" | "mutation" | "realtime" = "manual") => {
    try {
      let canonical: VenueJson;
      if (surface === "competition" || surface === "revisions") {
        const [overview, catalog, health] = await Promise.all([
          read({ competitionId, view: "overview" }, token),
          read({ competitionId, view: "catalog" }, token),
          read({ competitionId, view: "health" }, token),
        ]);
        canonical = { catalog, health, overview, serverSequence: venueNumber(overview.serverSequence) };
      } else if (surface === "planner") {
        const overview = await read({ competitionId, view: "overview" }, token);
        const plans = venueArray(overview.plans);
        const requested = new URLSearchParams(location.search).get("plan") ?? selectedPlanId;
        const planId = plans.some((item) => venueText(item.planId) === requested)
          ? requested : venueText(plans[0]?.planId);
        setSelectedPlanId(planId);
        if (!planId) canonical = { overview };
        else {
          const desk = await read({ planId, view: "desk" }, token);
          const plan = venueRecord(desk.plan);
          const pool = venueText(plan.venuePoolId)
            ? await read({ poolId: venueText(plan.venuePoolId), view: "pool" }, token)
            : {};
          canonical = { desk, overview, pool, serverSequence: venueNumber(plan.serverSequence) };
        }
      } else if (surface === "recurring-detail") {
        const series = await read({ seriesId, view: "series" }, token);
        const start = venueText(series.startDate);
        const end = venueText(series.endDate);
        const calendar = await read({ end, seriesId, start, view: "calendar" }, token);
        canonical = { calendar, series, serverSequence: venueNumber(series.serverSequence) };
      } else if (surface === "pools") {
        const catalog = await read({ clubId: targetClubId, competitionId: competitionId || null, view: "catalog" }, token);
        const selectedPool = selectedPoolId
          ? await read({ poolId: selectedPoolId, view: "pool" }, token)
          : null;
        canonical = selectedPool ? { catalog, pool: selectedPool } : { catalog };
      } else {
        canonical = await read({ clubId: targetClubId, competitionId: competitionId || null, view: "catalog" }, token);
      }
      setData(canonical);
      writeSeasonVenueCache(cacheScope, canonical);
      if (reason === "realtime") setMessage("Estado actualizado desde PostgreSQL.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar el estado canónico.");
    } finally {
      setLoading(false);
    }
  }, [cacheScope, clubId, competitionId, read, selectedPlanId, selectedPoolId, seriesId, surface]);

  useEffect(() => {
    const onlineListener = () => { setOnline(true); void reconcileRef.current?.(); };
    const offlineListener = () => setOnline(false);
    window.addEventListener("online", onlineListener);
    window.addEventListener("offline", offlineListener);
    return () => {
      window.removeEventListener("online", onlineListener);
      window.removeEventListener("offline", offlineListener);
    };
  }, []);

  useEffect(() => {
    const cached = readSeasonVenueCache(cacheScope);
    if (!cached) return;
    let active = true;
    queueMicrotask(() => {
      if (active) setData(cached);
    });
    return () => { active = false; };
  }, [cacheScope]);

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let timer: number | null = null;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(async ({ data: sessionData }) => {
      const session = sessionData.session;
      if (!active || !session) {
        setLoading(false);
        setMessage("Inicia sesión para consultar la gestión de campos.");
        return;
      }
      setAccessToken(session.access_token);
      setActorId(session.user.id);
      let targetClubId = new URLSearchParams(location.search).get("club") ?? "";
      if (!targetClubId && (surface === "recurring-list" || surface === "pools")) {
        const response = await fetch("/api/clubs/me", { cache: "no-store", headers: { Authorization: "Bearer " + session.access_token } });
        const body = await response.json() as VenueJson;
        const first = venueRecord(venueArray(body.clubs)[0]?.club);
        targetClubId = venueText(first.id);
      }
      if (active) setClubId(targetClubId);
      const reconcile = async () => { if (active) await load(session.access_token, targetClubId, "manual"); };
      reconcileRef.current = reconcile;
      await load(session.access_token, targetClubId, "initial");
      channel = client.channel("season-venue:" + (competitionId || seriesId || targetClubId || "home"))
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_venue_invalidations" }, (payload) => {
          const row = venueRecord(payload.new);
          const audience = venueText(row.audience_id);
          const entity = venueText(row.entity_id);
          if (![competitionId, seriesId, targetClubId, selectedPlanId, selectedPoolId].includes(audience)
              && ![seriesId, selectedPlanId, selectedPoolId].includes(entity)) return;
          if (timer) clearTimeout(timer);
          timer = window.setTimeout(() => { void load(session.access_token, targetClubId, "realtime"); }, 120);
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") {
            if (timer) clearTimeout(timer);
            timer = window.setTimeout(() => { void load(session.access_token, targetClubId, "realtime"); }, 250);
          }
        });
    });
    return () => {
      active = false;
      reconcileRef.current = null;
      if (timer) clearTimeout(timer);
      if (channel) void client.removeChannel(channel);
    };
  }, [competitionId, load, selectedPlanId, selectedPoolId, seriesId, surface]);

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: VenueJson) {
    if (!accessToken || !actorId || !online) {
      setMessage("Sin conexión: no se ha enviado ni confirmado ningún cambio.");
      return;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Enviando intención al servidor...");
    try {
      const response = await clientWriteFetch("api:season-venue-command", "/api/season-venues/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: "Bearer " + accessToken, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || venueText(body.error) || "Operación rechazada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await load(accessToken, clubId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "La operación no fue confirmada.";
      setMessage(/STALE/i.test(detail) ? "La revisión cambió. Se ha recargado el estado canónico." : detail);
      if (/STALE/i.test(detail)) await load(accessToken, clubId, "manual");
    } finally {
      setBusy(false);
    }
  }

  const overview = venueRecord(data?.overview);
  const catalog = venueRecord(data?.catalog ?? (surface === "recurring-list" || surface === "pools" ? data : null));
  const desk = venueRecord(data?.desk);
  const plan = venueRecord(desk.plan);
  const revision = venueRecord(desk.revision);
  const quality = venueRecord(desk.quality);
  const pool = venueRecord(data?.pool);
  const poolHeader = venueRecord(pool.pool);
  const pools = venueArray(catalog.venuePools);
  const seriesList = venueArray(catalog.recurringSeries);
  const plans = venueArray(overview.plans ?? catalog.allocationPlans);
  const items = venueArray(desk.items);
  const memberships = venueArray(pool.memberships);
  const authorizations = venueArray(pool.authorizations);
  const constraints = venueArray(desk.constraints);
  const conflicts = venueArray(desk.conflicts);
  const locks = venueArray(desk.locks);
  const series = venueRecord(data?.series);
  const calendar = venueRecord(data?.calendar);
  const counts = venueRecord(overview.counts);

  const competitionBase = `/competiciones/${competitionId}/gestion/campos`;
  const links = competitionId ? [
    ["Resumen", competitionBase, surface === "competition"],
    ["Plan", `${competitionBase}/plan`, surface === "planner"],
    ["Revisiones", `${competitionBase}/revisiones`, surface === "revisions"],
  ] as const : [
    ["Bloques", "/clubes/gestionar/campos/bloques", surface.includes("recurring")],
    ["Pools", "/clubes/gestionar/campos/pools", surface === "pools"],
    ["Reservas", "/reservas/recurrentes", surface.includes("recurring")],
    ["Campos", "/clubes/gestionar/campos", false],
  ] as const;

  function createSeries(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const purpose = formText(form, "purpose");
    const targetId = formText(form, "targetId");
    void command("recurring_series.create", "", 0, {
      bufferMinutes: Number(formText(form, "bufferMinutes") || 0),
      competitionId: purpose === "COMPETITION_RECURRING_BLOCK" ? targetId : null,
      durationMinutes: Number(formText(form, "durationMinutes") || 70),
      endDate: formText(form, "endDate"),
      frequency: formText(form, "frequency"),
      localStartTime: formText(form, "localStartTime"),
      modality: formText(form, "modality"),
      pitchId: formText(form, "pitchId"),
      purpose,
      reasonCode: "RECURRING_SERIES_CREATE",
      startDate: formText(form, "startDate"),
      teamId: purpose === "TEAM_RECURRING_BLOCK" ? targetId : null,
      timezone: formText(form, "timezone") || "Europe/Madrid",
      weekday: Number(formText(form, "weekday")),
    });
  }

  function createPool(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("venue_pool.create", "", 0, {
      competitionId: formText(form, "competitionId"),
      editionId: formText(form, "editionId"),
      name: formText(form, "name"),
      reasonCode: "VENUE_POOL_CREATE",
      visibility: "competition_staff",
    });
  }

  function createPlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("allocation_plan.create", "", 0, {
      competitionId,
      editionId: formText(form, "editionId"),
      mode: formText(form, "mode"),
      reasonCode: "ALLOCATION_PLAN_CREATE",
      ruleRevisionId: formText(form, "ruleRevisionId"),
      schedulePlanId: formText(form, "schedulePlanId"),
      scheduleRevisionId: formText(form, "scheduleRevisionId"),
      stageId: formText(form, "stageId"),
      venuePoolId: formText(form, "venuePoolId"),
      venueRequired: form.get("venueRequired") === "on",
    });
  }

  function offerPool(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const recurringSeriesId = formText(form, "recurringSeriesId");
    const reservationId = formText(form, "reservationId");
    void command("venue_pool.offer", selectedPoolId, venueNumber(poolHeader.revision), {
      allowedWeekdays: formText(form, "allowedWeekdays").split(",").map((value) => Number(value.trim())).filter((value) => value >= 1 && value <= 7),
      capacityPerSlot: Number(formText(form, "capacityPerSlot") || 1),
      expiresAt: formText(form, "expiresAt") || null,
      localEndTime: formText(form, "localEndTime"),
      localStartTime: formText(form, "localStartTime"),
      modalities: formText(form, "modalities").split(",").map((value) => value.trim().toUpperCase()).filter(Boolean),
      ownerClubId: formText(form, "ownerClubId"),
      pitchIds: formText(form, "pitchIds").split(",").map((value) => value.trim()).filter(Boolean),
      priority: Number(formText(form, "priority") || 100),
      reasonCode: "VENUE_POOL_OFFER",
      recurringSeriesId: recurringSeriesId || null,
      reservationId: reservationId || null,
      sourceKind: formText(form, "sourceKind"),
      validFrom: formText(form, "validFrom"),
      validUntil: formText(form, "validUntil"),
      venueId: formText(form, "venueId"),
      visibility: "competition_staff",
    });
  }

  function createConstraint(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const [constraintKind, constraintCode] = formText(form, "constraint").split(":");
    void command("allocation_constraint.create", venueText(plan.planId), venueNumber(plan.revision), {
      constraintCode,
      constraintKind,
      parameters: {},
      reason: formText(form, "reason"),
      scopeId: formText(form, "scopeId") || null,
      scopeKind: formText(form, "scopeKind"),
      weight: Number(formText(form, "weight") || 1),
    });
  }

  function plannerCommand(action: string, payload: VenueJson = { reasonCode: "SEASON_PLANNER_ACTION" }) {
    void command(action, venueText(plan.planId), venueNumber(plan.revision), payload);
  }

  const heading = surface === "planner" ? "Season Venue Planner"
    : surface === "revisions" ? "Revisiones de campos"
      : surface === "pools" ? "Pools autorizados"
        : surface === "recurring-detail" ? "Bloque recurrente"
          : surface === "recurring-list" ? "Bloques recurrentes"
            : "Campos de competición";

  return <OfficialProductShellV2
    active={competitionId ? "competir" : "equipo"}
    context={{ detail: competitionId || clubId || "Operación canónica", id: competitionId || clubId || "season-venue", status: online ? "Servidor conectado" : "Solo lectura offline", title: heading, type: competitionId ? "competition" : "club" }}
    perspective={competitionId ? "league-organizer" : "club-organizer"}
  >
    <main className={styles.root}>
      <nav className={styles.subnav} aria-label="Gestión de campos de temporada">
        {links.map(([label, href, active]) => <Link data-active={active} href={href} key={href}>{label}</Link>)}
      </nav>
      <div className={styles.content}>
        <header className={styles.heading}>
          <div><span className={styles.eyebrow}>Autoridad central · Wave 9B</span><h1>{heading}</h1><p>Horarios deportivos congelados, campos autorizados y reservas canónicas. El navegador solo envía intenciones.</p></div>
          <div className={styles.status}><strong className={!online ? styles.offline : undefined}>{online ? "Sincronizado" : "Offline"}</strong><small>{loading ? "Recuperando snapshot..." : `Revisión ${venueNumber(plan.revision || series.revision || overview.serverSequence)}`}</small></div>
        </header>
        {message ? <p className={styles.notice} data-error={/rechaz|error|no se|sin conexión|forbidden|invalid/i.test(message)}>{message}</p> : null}

        {surface === "competition" ? <>
          <div className={styles.metrics}>
            <Metric label="Pools" value={counts.pools} /><Metric label="Planes" value={counts.plans} />
            <Metric label="Publicados" value={counts.published} /><Metric label="Sin campo" value={counts.unassignedMatches} />
            <Metric label="Holds" value={counts.activeHolds} /><Metric label="Violaciones hard" value={counts.hardViolations} />
          </div>
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Planes de asignación</h2><p>Una revisión canónica por propuesta.</p></div></div>
            <div className={styles.grid}>{plans.map((entry) => <article className={styles.card} data-alert={venueText(entry.status) === "stale" || venueText(entry.status) === "conflicted"} key={venueText(entry.planId)}><StatusChip value={entry.status} /><h3>{seasonVenueMode(entry.mode)}</h3><p>Revisión {venueNumber(entry.revision)} · secuencia {venueNumber(entry.serverSequence)}</p><footer><Link className={styles.buttonSecondary} href={`${competitionBase}/plan?plan=${venueText(entry.planId)}`}>Abrir plan</Link></footer></article>)}</div>
            {!plans.length ? <p className={styles.empty}>No existe todavía un plan de campos para esta competición.</p> : null}
          </section>
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Nuevo plan</h2><p>Usa únicamente revisiones ya publicadas y un pool autorizado.</p></div></div>
            <form className={styles.form} onSubmit={createPlan}>
              {[["editionId","Edition ID"],["stageId","Stage ID"],["schedulePlanId","Schedule Plan ID"],["scheduleRevisionId","Schedule Revision ID"],["ruleRevisionId","Rule Revision ID"],["venuePoolId","Venue Pool ID"]].map(([name,label]) => <label key={name}>{label}<input name={name} required /></label>)}
              <label>Modo<select name="mode" defaultValue="AUTOMATIC"><option value="AUTOMATIC">Automático</option><option value="MANUAL_ASSISTED">Manual asistido</option><option value="HYBRID">Híbrido</option></select></label>
              <label><input defaultChecked name="venueRequired" type="checkbox" /> Campo obligatorio</label>
              <div className={styles.formActions}><button className={styles.button} disabled={busy || !online}>Crear plan</button></div>
            </form>
          </section>
        </> : null}

        {surface === "planner" ? <>
          {!venueText(plan.planId) ? <p className={styles.empty}>Crea un plan desde el resumen o selecciona uno existente.</p> : <>
            <div className={styles.metrics}>
              <Metric label="Asignados" value={revision.assignedCount} /><Metric label="Sin asignar" value={revision.unassignedCount} />
              <Metric label="Conflictos" value={conflicts.length} /><Metric label="Locks" value={locks.length} />
              <Metric label="Candidatos" value={revision.candidateCount} /><Metric label="Quality" value={quality.score} />
            </div>
            <div className={styles.portraitTabs}>{(["matches","fields","assignment","conflicts","summary"] as Pane[]).map((value) => <button data-active={pane === value} key={value} onClick={() => setPane(value)} type="button">{value === "matches" ? "Partidos" : value === "fields" ? "Campos" : value === "assignment" ? "Asignación" : value === "conflicts" ? "Conflictos" : "Resumen"}</button>)}</div>
            <div className={styles.planner}>
              <aside className={styles.pane} data-active={pane === "matches" || pane === "fields"}><h2>Jornadas y campos</h2><div className={styles.scroll}>{memberships.map((entry) => <article className={styles.card} key={venueText(entry.membershipId)}><StatusChip value={entry.status} /><h3>{venueText(entry.pitchName) || "Pitch autorizado"}</h3><p>{venueText(entry.modality)} · prioridad {venueNumber(entry.priority)} · {venueNumber(entry.consumedCount)} consumidos</p></article>)}{!memberships.length ? <p className={styles.empty}>El pool no tiene campos activos.</p> : null}</div></aside>
              <section className={styles.pane} data-active={pane === "assignment" || pane === "matches"}><h2>Partidos y asignaciones</h2><div className={styles.scroll}>{items.map((item) => <article className={styles.match} key={venueText(item.itemId)}><div><strong>{venueText(item.homeEntryId).slice(0,8)} vs {venueText(item.awayEntryId).slice(0,8)}</strong><small>{new Date(venueText(item.scheduledStart)).toLocaleString("es-ES")} · {venueText(item.pitchName) || "Sin campo"}</small></div><StatusChip value={item.assignmentStatus} /><div className={styles.matchActions}><select className={styles.compactSelect} aria-label="Campo" defaultValue={venueText(item.pitchId)} id={`pitch-${venueText(item.itemId)}`}><option value="">Campo...</option>{memberships.map((entry) => <option key={venueText(entry.membershipId)} value={venueText(entry.pitchId)}>{venueText(entry.pitchName)}</option>)}</select><button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => { const input = document.getElementById(`pitch-${venueText(item.itemId)}`) as HTMLSelectElement | null; if (input?.value) plannerCommand(venueText(item.pitchId) ? "allocation.item.move" : "allocation.item.assign", { canonicalMatchId: venueText(item.canonicalMatchId), pitchId: input.value, reasonCode: "MANUAL_FIELD_ASSIGNMENT" }); }} title="Asignar campo" type="button">Asignar</button><select className={styles.compactSelect} aria-label="Partido con el que intercambiar" defaultValue="" id={`swap-${venueText(item.itemId)}`}><option value="">Intercambiar...</option>{items.filter((candidate) => candidate.itemId !== item.itemId && venueText(candidate.pitchId)).map((candidate) => <option key={venueText(candidate.itemId)} value={venueText(candidate.canonicalMatchId)}>{venueText(candidate.homeEntryId).slice(0,6)} vs {venueText(candidate.awayEntryId).slice(0,6)}</option>)}</select><button className={styles.buttonSecondary} disabled={busy || !online || !venueText(item.pitchId)} onClick={() => { const input = document.getElementById(`swap-${venueText(item.itemId)}`) as HTMLSelectElement | null; if (input?.value) plannerCommand("allocation.item.swap", { canonicalMatchId: venueText(item.canonicalMatchId), otherCanonicalMatchId: input.value, reasonCode: "MANUAL_FIELD_SWAP" }); }} type="button">Swap</button><button className={styles.buttonSecondary} disabled={busy || !online || !venueText(item.pitchId)} onClick={() => plannerCommand("allocation.lock.create", { canonicalMatchId: venueText(item.canonicalMatchId), lockType: "MATCH_TO_PITCH", pitchId: venueText(item.pitchId), reason: "Bloqueo manual del organizador" })} title="Bloquear asignación" type="button">Lock</button><button className={styles.danger} disabled={busy || !online || !venueText(item.pitchId)} onClick={() => plannerCommand("allocation.item.remove", { canonicalMatchId: venueText(item.canonicalMatchId), reasonCode: "MANUAL_FIELD_REMOVAL" })} type="button">Retirar</button></div></article>)}{!items.length ? <p className={styles.empty}>Congela los inputs y genera una revisión para ver los partidos.</p> : null}</div></section>
              <aside className={styles.pane} data-active={pane === "conflicts" || pane === "summary"}><h2>Quality y conflictos</h2><div className={styles.quality}><div><strong>{venueNumber(quality.score)}</strong><small>/100</small></div></div><dl className={styles.qualityBreakdown}><div><dt>Hard</dt><dd>{venueNumber(quality.hardViolations)}</dd></div><div><dt>Sin campo</dt><dd>{venueNumber(quality.unassignedMatches)}</dd></div><div><dt>Recurrentes</dt><dd>{venueNumber(quality.recurringBlockUsage)}</dd></div><div><dt>Cambios</dt><dd>{venueNumber(quality.venueChanges)}</dd></div><div><dt>Utilización</dt><dd>{venueNumber(quality.pitchUtilization)}</dd></div><div><dt>Slots premium</dt><dd>{venueNumber(quality.premiumSlotBalance)}</dd></div><div><dt>Overrides</dt><dd>{venueNumber(quality.manualOverrideCount)}</dd></div><div><dt>Locks</dt><dd>{venueNumber(quality.lockedAssignments)}</dd></div><div><dt>Avisos</dt><dd>{venueArray(quality.warnings).length}</dd></div><div><dt>Distancia</dt><dd>{venueText(venueRecord(quality.travelEstimate).status) || "No calculada"}</dd></div></dl><p className={styles.qualityExplanation}>{venueText(quality.explanation)}</p><div className={styles.scroll}>{conflicts.map((entry) => <article className={styles.card} data-alert="true" key={venueText(entry.conflictId)}><StatusChip value={entry.severity} /><h3>{venueText(entry.conflictCode)}</h3><p>{venueText(entry.publicExplanation)}</p></article>)}{!conflicts.length ? <p className={styles.empty}>Sin conflictos activos en esta revisión.</p> : null}</div></aside>
            </div>
            <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Restricciones y locks</h2><p>La comparación y la autoridad permanecen en PostgreSQL.</p></div></div><div className={styles.twoColumns}><div><h3>Restricciones activas</h3>{constraints.map((entry) => <article className={styles.compactRow} key={venueText(entry.constraintId)}><span><strong>{venueText(entry.kind)} · {venueText(entry.code)}</strong><small>{venueText(entry.scopeKind)} · peso {venueNumber(entry.weight)}</small></span><button className={styles.danger} disabled={busy || !online} onClick={() => plannerCommand("allocation_constraint.remove", { constraintId: venueText(entry.constraintId), reasonCode: "CONSTRAINT_REMOVED" })} type="button">Quitar</button></article>)}{!constraints.length ? <p className={styles.empty}>Sin restricciones adicionales.</p> : null}<form className={styles.inlineForm} onSubmit={createConstraint}><label>Regla<select name="constraint"><option value="HARD:MATCH_TIME_FIXED">Hard · horario fijo</option><option value="HARD:NO_RESERVATION_OVERLAP">Hard · sin solapes</option><option value="HARD:VENUE_POOL_AUTHORIZED">Hard · pool autorizado</option><option value="SOFT:PREFERRED_VENUE">Soft · Venue preferido</option><option value="SOFT:PREFERRED_PITCH">Soft · Pitch preferido</option><option value="SOFT:MAXIMIZE_RECURRING_BLOCK_USAGE">Soft · usar bloques</option><option value="SOFT:BALANCE_PITCH_USAGE">Soft · equilibrar uso</option><option value="SOFT:FINAL_ON_FEATURED_PITCH">Soft · final destacada</option></select></label><label>Ámbito<select name="scopeKind"><option>PLAN</option><option>ROUND</option><option>MATCH</option><option>TEAM</option><option>VENUE</option><option>PITCH</option></select></label><label>ID de ámbito<input name="scopeId" /></label><label>Peso<input defaultValue="1" min="0" name="weight" type="number" /></label><label>Motivo<input name="reason" required /></label><button className={styles.buttonSecondary} disabled={busy || !online}>Añadir</button></form></div><div><h3>Locks activos</h3>{locks.map((entry) => <article className={styles.compactRow} key={venueText(entry.lockId)}><span><strong>{venueText(entry.lockType)}</strong><small>{venueText(entry.canonicalMatchId).slice(0, 12)} · revisión {venueNumber(entry.revision)}</small></span><button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => plannerCommand("allocation.lock.remove", { lockId: venueText(entry.lockId), reasonCode: "MANUAL_UNLOCK" })} type="button">Desbloquear</button></article>)}{!locks.length ? <p className={styles.empty}>Sin locks manuales.</p> : null}</div></div></section>
            <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Flujo autoritativo</h2><p>Las acciones incompatibles serán rechazadas por revisión obsoleta.</p></div></div><div className={styles.grid}>
              <button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => plannerCommand("allocation_inputs.freeze")} type="button">Congelar inputs</button>
              <button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => plannerCommand(venueText(revision.revisionId) ? "allocation.regenerate" : "allocation.generate", { reasonCode: "SEASON_ALLOCATION_GENERATE", searchBudget: 10000, seed: `season-${competitionId}` })} type="button">Generar propuesta</button>
              <button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => plannerCommand("allocation.hold", { expiresInMinutes: 60, reasonCode: "SEASON_ALLOCATION_HOLD" })} type="button">Crear holds</button>
              <button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => plannerCommand("allocation.validate")} type="button">Validar</button>
              <button className={styles.button} disabled={busy || !online} onClick={() => plannerCommand("allocation.publish")} type="button">Publicar asignación</button>
              <button className={styles.danger} disabled={busy || !online} onClick={() => plannerCommand("allocation.cancel")} type="button">Cancelar plan</button>
            </div></section>
          </>}
        </> : null}

        {surface === "revisions" ? <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Historia preservada</h2><p>Cada propuesta mantiene seed, checksums y secuencia del servidor.</p></div></div><div className={styles.grid}>{plans.map((entry) => <article className={styles.card} key={venueText(entry.planId)}><StatusChip value={entry.status} /><h3>{seasonVenueMode(entry.mode)}</h3><p>Plan {venueText(entry.planId)} · revisión {venueNumber(entry.revision)}</p><footer><Link className={styles.buttonSecondary} href={`${competitionBase}/plan?plan=${venueText(entry.planId)}`}>Comparar en planner</Link></footer></article>)}</div>{!plans.length ? <p className={styles.empty}>No hay revisiones todavía.</p> : null}</section> : null}

        {surface === "recurring-list" ? <>
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Series finitas</h2><p>Semanal o quincenal, siempre con fecha final.</p></div></div><div className={styles.grid}>{seriesList.map((entry) => <article className={styles.card} key={venueText(entry.seriesId)}><StatusChip value={entry.status} /><h3>{venueText(entry.modality)} · {venueText(entry.frequency)}</h3><p>{venueText(entry.startDate)} → {venueText(entry.endDate)} · {venueText(entry.localStartTime)}</p><footer><Link className={styles.buttonSecondary} href={`/reservas/recurrentes/${venueText(entry.seriesId)}`}>Abrir serie</Link></footer></article>)}</div>{!seriesList.length ? <p className={styles.empty}>No hay bloques recurrentes para este Club.</p> : null}</section>
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Crear bloque</h2><p>El Pitch determina el Club propietario; PostgreSQL valida capacidad y permisos.</p></div></div><form className={styles.form} onSubmit={createSeries}>
            <label>Pitch ID<input name="pitchId" required /></label><label>Finalidad<select name="purpose"><option value="TEAM_RECURRING_BLOCK">Equipo</option><option value="COMPETITION_RECURRING_BLOCK">Competición</option></select></label><label>Team / Competition ID<input name="targetId" required /></label><label>Modalidad<select name="modality"><option>F7</option><option>F5</option><option>F11</option><option>FUTSAL</option></select></label><label>Frecuencia<select name="frequency"><option>WEEKLY</option><option>BIWEEKLY</option></select></label><label>Día (1-7)<input max="7" min="1" name="weekday" required type="number" /></label><label>Hora<input name="localStartTime" required type="time" /></label><label>Duración<input defaultValue="70" name="durationMinutes" type="number" /></label><label>Buffer<input defaultValue="5" name="bufferMinutes" type="number" /></label><label>Inicio<input name="startDate" required type="date" /></label><label>Fin<input name="endDate" required type="date" /></label><label>Zona<input defaultValue="Europe/Madrid" name="timezone" /></label><div className={styles.formActions}><button className={styles.button} disabled={busy || !online}>Crear bloque</button></div>
          </form></section>
        </> : null}

        {surface === "recurring-detail" ? <>
          <div className={styles.metrics}><Metric label="Planificadas" value={venueRecord(series.occurrenceCounts).planned} /><Metric label="Reservadas" value={venueRecord(series.occurrenceCounts).reserved} /><Metric label="Consumidas" value={venueRecord(series.occurrenceCounts).consumed} /><Metric label="Excluidas" value={venueRecord(series.occurrenceCounts).excluded} /></div>
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>{venueText(series.modality)} · {venueText(series.frequency)}</h2><p>{venueText(series.startDate)} → {venueText(series.endDate)} · revisión {venueNumber(series.revision)}</p></div><StatusChip value={series.status} /></div><div className={styles.grid}>{venueArray(calendar.items).map((item) => <article className={styles.card} key={venueText(item.occurrenceId)}><StatusChip value={item.status} /><h3>{venueText(item.occurrenceDate)}</h3><p>{new Date(venueText(item.startsAt)).toLocaleTimeString("es-ES")} · Pitch {venueText(item.pitchId).slice(0,8)}</p></article>)}</div></section>
          <section className={styles.section}><div className={styles.grid}>{[["recurring_series.validate","Validar"],["recurring_series.offer","Ofrecer"],["recurring_series.accept","Aceptar"],["recurring_series.publish","Publicar"],["recurring_series.materialize","Materializar"],["recurring_series.pause","Pausar"],["recurring_series.resume","Reanudar"],["recurring_series.complete","Completar"],["recurring_series.end","Finalizar"]].map(([action,label]) => <button className={styles.buttonSecondary} disabled={busy || !online} key={action} onClick={() => void command(action, seriesId, venueNumber(series.revision), { reasonCode: "RECURRING_SERIES_ACTION" })} type="button">{label}</button>)}<button className={styles.danger} disabled={busy || !online} onClick={() => void command("recurring_series.cancel", seriesId, venueNumber(series.revision), { reasonCode: "RECURRING_SERIES_CANCEL" })} type="button">Cancelar</button></div></section>
        </> : null}

        {surface === "pools" ? <>
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Bolsas autorizadas</h2><p>La visibilidad pública de un Venue nunca concede autoridad.</p></div></div><div className={styles.grid}>{pools.map((entry) => <article className={styles.card} data-selected={selectedPoolId === venueText(entry.poolId)} key={venueText(entry.poolId)}><StatusChip value={entry.status} /><h3>{venueText(entry.name)}</h3><p>{venueNumber(entry.activeMemberships)} Pitches · revisión {venueNumber(entry.revision)}</p><footer><button className={styles.buttonSecondary} onClick={() => setSelectedPoolId(venueText(entry.poolId))} type="button">Seleccionar</button><button className={styles.buttonSecondary} disabled={busy || !online} onClick={() => void command("venue_pool.activate", venueText(entry.poolId), venueNumber(entry.revision), { reasonCode: "VENUE_POOL_ACTIVATE" })} type="button">Activar</button></footer></article>)}</div>{!pools.length ? <p className={styles.empty}>No hay pools visibles para este Club.</p> : null}</section>
          {selectedPoolId && venueText(poolHeader.poolId) ? <section className={styles.section}><div className={styles.sectionHeader}><div><h2>{venueText(poolHeader.name)}</h2><p>Oferta, aceptación y membresías del snapshot seleccionado.</p></div><StatusChip value={poolHeader.status} /></div><div className={styles.twoColumns}><div><h3>Autorizaciones</h3>{authorizations.map((entry) => <article className={styles.compactRow} key={venueText(entry.authorizationId)}><span><strong>{venueText(entry.venueName)} · {venueText(entry.sourceKind)}</strong><small>{venueText(entry.validFrom)} → {venueText(entry.validUntil)} · revisión {venueNumber(entry.revision)}</small></span><StatusChip value={entry.status} /><button className={styles.buttonSecondary} disabled={busy || !online || venueText(entry.status).toLowerCase() !== "offered"} onClick={() => void command("venue_pool.accept", venueText(entry.authorizationId), venueNumber(entry.revision), { reasonCode: "VENUE_AUTHORIZATION_ACCEPT" })} type="button">Aceptar</button></article>)}{!authorizations.length ? <p className={styles.empty}>Este pool todavía no tiene ofertas.</p> : null}</div><div><h3>Pitches activos</h3>{memberships.map((entry) => <article className={styles.compactRow} key={venueText(entry.membershipId)}><span><strong>{venueText(entry.pitchName)}</strong><small>{venueText(entry.modality)} · {venueNumber(entry.consumedCount)}/{venueNumber(entry.capacityLimit)}</small></span><StatusChip value={entry.status} /></article>)}{!memberships.length ? <p className={styles.empty}>Se materializan al activar el pool aceptado.</p> : null}</div></div><form className={styles.form} onSubmit={offerPool}><label>Club propietario<input name="ownerClubId" required /></label><label>Venue ID<input name="venueId" required /></label><label>Pitch IDs (coma)<input name="pitchIds" required /></label><label>Modalidades (coma)<input defaultValue="F7" name="modalities" required /></label><label>Origen<select name="sourceKind"><option>SELF_MANAGED</option><option>CLUB_OFFER</option><option>RECURRING_SERIES</option><option>CONFIRMED_RESERVATION</option><option>AVAILABILITY_AGREEMENT</option></select></label><label>Recurring series ID<input name="recurringSeriesId" /></label><label>Reservation ID<input name="reservationId" /></label><label>Días 1-7 (coma)<input defaultValue="1,2,3,4,5,6,7" name="allowedWeekdays" /></label><label>Desde<input name="validFrom" required type="date" /></label><label>Hasta<input name="validUntil" required type="date" /></label><label>Hora inicio<input name="localStartTime" required type="time" /></label><label>Hora fin<input name="localEndTime" required type="time" /></label><label>Capacidad<input defaultValue="1" min="1" name="capacityPerSlot" type="number" /></label><label>Prioridad<input defaultValue="100" min="1" name="priority" type="number" /></label><label>Expira<input name="expiresAt" type="datetime-local" /></label><div className={styles.formActions}><button className={styles.button} disabled={busy || !online}>Ofrecer autorización</button></div></form></section> : null}
          <section className={styles.section}><div className={styles.sectionHeader}><div><h2>Crear pool</h2><p>Después se ofrece con Venues, Pitches y ventana explícitos.</p></div></div><form className={styles.form} onSubmit={createPool}><label>Competition ID<input defaultValue={competitionId} name="competitionId" required /></label><label>Edition ID<input name="editionId" required /></label><label>Nombre<input name="name" required /></label><div className={styles.formActions}><button className={styles.button} disabled={busy || !online}>Crear pool</button></div></form></section>
        </> : null}
      </div>
    </main>
  </OfficialProductShellV2>;
}
