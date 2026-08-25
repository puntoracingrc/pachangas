"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  leagueOperationalActionLabel,
  leagueOperationalArray,
  leagueOperationalBoolean,
  leagueOperationalExceptionsCacheVersion,
  leagueOperationalExceptionsRealtimeTable,
  leagueOperationalFlagsEnabled,
  leagueOperationalNumber,
  leagueOperationalRecord,
  leagueOperationalStatusTone,
  leagueOperationalText,
  type LeagueOperationalExceptionAction,
  type LeagueOperationalJson,
} from "../league-operational-exceptions-contract";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import { ProductState } from "./product-state";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./league-operational-exceptions-client.module.css";

export type LeagueOperationalSurface = "decisions" | "incidents" | "match" | "my" | "postponements" | "public";

type Props = {
  competitionId?: string;
  matchId?: string;
  previewData?: LeagueOperationalJson | null;
  surface: LeagueOperationalSurface;
};

type Command = (
  action: LeagueOperationalExceptionAction,
  expectedRevision: number,
  payload?: LeagueOperationalJson,
  aggregateOverride?: string,
) => Promise<void>;

function endpointFor({ competitionId = "", matchId = "", surface }: Props) {
  if (surface === "match") return `/api/competitions/operational-exceptions/match/${competitionId}/${matchId}`;
  if (surface === "public") return `/api/competitions/operational-exceptions/public/${competitionId}/${matchId}`;
  if (surface === "postponements") return `/api/competitions/operational-exceptions/postponements/${competitionId}`;
  if (surface === "incidents") return `/api/competitions/operational-exceptions/incidents/${competitionId}`;
  if (surface === "decisions") return `/api/competitions/operational-exceptions/decisions/${competitionId}`;
  return "/api/competitions/operational-exceptions/my";
}

function cacheKey(surface: LeagueOperationalSurface, identity: string, userId: string) {
  return `pachangas-league-operational-read-v1:${surface}:${identity}:${userId || "public"}`;
}

function cacheLifetime(surface: LeagueOperationalSurface, data: LeagueOperationalJson) {
  const status = leagueOperationalText(leagueOperationalRecord(data.context).status);
  const publicStatus = leagueOperationalText(data.status);
  if (["cancelled", "official", "retired"].includes(status || publicStatus)) return 7 * 24 * 60 * 60 * 1000;
  if (surface === "match" || surface === "public") return 5 * 60 * 1000;
  return 2 * 60 * 1000;
}

function readCache(key: string) {
  try {
    const envelope = leagueOperationalRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (leagueOperationalNumber(envelope.version) !== leagueOperationalExceptionsCacheVersion) return null;
    if (Date.now() > leagueOperationalNumber(envelope.expiresAt)) return null;
    return leagueOperationalRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, surface: LeagueOperationalSurface, data: LeagueOperationalJson) {
  try {
    window.localStorage.setItem(key, JSON.stringify({
      data,
      expiresAt: Date.now() + cacheLifetime(surface, data),
      revision: leagueOperationalNumber(data.revision),
      serverSequence: leagueOperationalNumber(data.serverSequence),
      storedAt: new Date().toISOString(),
      version: leagueOperationalExceptionsCacheVersion,
    }));
  } catch {
    // Optional read cache only. PostgreSQL remains authoritative.
  }
}

function dateLabel(value: unknown, timezone = "Europe/Madrid") {
  const parsed = new Date(leagueOperationalText(value));
  if (Number.isNaN(parsed.getTime())) return "Pendiente";
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone || "Europe/Madrid",
  }).format(parsed);
}

function statusChip(value: unknown) {
  const label = leagueOperationalText(value).replaceAll("_", " ") || "pendiente";
  return <StatusChip tone={leagueOperationalStatusTone(value)}>{label}</StatusChip>;
}

function managesEntry(data: LeagueOperationalJson, entryId: unknown) {
  const context = leagueOperationalRecord(data.context);
  const permissions = leagueOperationalRecord(data.permissions);
  const selected = leagueOperationalText(entryId);
  return (selected === leagueOperationalText(context.homeEntryId) && leagueOperationalBoolean(permissions.manageHome))
    || (selected === leagueOperationalText(context.awayEntryId) && leagueOperationalBoolean(permissions.manageAway));
}

function invalidationMatches(props: Props, payload: unknown) {
  const row = leagueOperationalRecord(leagueOperationalRecord(payload).new);
  const entityType = leagueOperationalText(row.entity_type);
  if (entityType === "league_operational_exceptions_flags") return true;
  if (props.competitionId && leagueOperationalText(row.competition_id) !== props.competitionId) return false;
  return [
    "administrative_decision", "fixture_change", "league_operational_exceptions",
    "match", "match_suspension", "operational_incident", "operational_request",
    "result", "round", "standings",
  ].includes(entityType);
}

function commonPayload(reasonCode: string, publicSummary: string, reasonText: string, evidence: string) {
  return {
    evidenceRefs: evidence.split(",").map((item) => item.trim()).filter(Boolean),
    publicSummary: publicSummary.trim(),
    reasonCode: reasonCode.trim() || "OTHER",
    reasonText: reasonText.trim(),
  };
}

function MatchTimeline({ data }: { data: LeagueOperationalJson }) {
  const context = leagueOperationalRecord(data.context);
  const original = leagueOperationalRecord(data.originalSchedule);
  const effective = leagueOperationalRecord(data.effectiveFixtureChange);
  const timezone = leagueOperationalText(context.timezone) || "Europe/Madrid";
  return <section className={styles.timelineBand}>
    <SectionHeader eyebrow="Lineage canónico" title="Programación" />
    <div className={styles.timelineGrid}>
      <div><span>Original R4B</span><strong>{dateLabel(original.scheduledStart, timezone)}</strong><small>{leagueOperationalText(original.venueLabel) || "Sede pendiente"}</small></div>
      <div><span>Estado efectivo</span><strong>{dateLabel(context.scheduledStart, timezone)}</strong><small>{leagueOperationalText(context.venueLabel) || "Sede pendiente"}</small></div>
      <div><span>Último cambio</span><strong>{leagueOperationalText(effective.changeType).replaceAll("_", " ") || "Sin cambios"}</strong><small>{leagueOperationalText(effective.publicSummary) || "Calendario original vigente"}</small></div>
      <div><span>Contexto</span>{statusChip(context.status)}<small>r{leagueOperationalNumber(context.revision)} · seq {leagueOperationalNumber(context.serverSequence)}</small></div>
    </div>
  </section>;
}

function RequestList({ command, data, disabled }: { command: Command; data: LeagueOperationalJson; disabled: boolean }) {
  const context = leagueOperationalRecord(data.context);
  const permissions = leagueOperationalRecord(data.permissions);
  const manager = leagueOperationalBoolean(permissions.manageOperations);
  return <section className={styles.listBand}>
    <SectionHeader eyebrow="Solicitudes" title="Aplazamientos" />
    <div className={styles.itemGrid}>
      {leagueOperationalArray(data.postponementRequests).map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}>
        <header>{statusChip(item.status)}<small>seq {leagueOperationalNumber(item.serverSequence)}</small></header>
        <strong>{dateLabel(item.proposedStart, leagueOperationalText(item.proposedTimezone))}</strong>
        <p>{leagueOperationalText(item.publicSummary) || leagueOperationalText(item.reasonCode)}</p>
        <small>Responde antes de {dateLabel(item.responseDeadline)}</small>
        {leagueOperationalText(item.status) === "awaiting_response" ? <div className={styles.inlineActions}>
          {managesEntry(data, leagueOperationalText(item.teamResponse) === "COUNTERPROPOSED" ? item.requestingEntryId : item.respondingEntryId) ? <>
            <button disabled={disabled} onClick={() => void command("postponement.respond", leagueOperationalNumber(context.revision), { requestId: item.id, responseKind: "ACCEPT", reasonCode: "TEAM_ACCEPT", publicSummary: "Solicitud aceptada por el rival." })} type="button">Aceptar</button>
            <button disabled={disabled} onClick={() => void command("postponement.respond", leagueOperationalNumber(context.revision), { requestId: item.id, responseKind: "REJECT", reasonCode: "TEAM_REJECT", publicSummary: "Solicitud rechazada por el rival." })} type="button">Rechazar</button>
          </> : null}
          {managesEntry(data, item.requestingEntryId) ? <button disabled={disabled} onClick={() => void command("postponement.withdraw", leagueOperationalNumber(context.revision), { requestId: item.id, reasonCode: "WITHDRAWN", publicSummary: "Solicitud retirada." })} type="button">Retirar</button> : null}
          {manager && leagueOperationalText(item.teamResponse) === "ACCEPTED" ? <>
            <button disabled={disabled} onClick={() => void command("postponement.respond", leagueOperationalNumber(context.revision), { requestId: item.id, responseKind: "APPROVE", reasonCode: "ORGANIZER_APPROVAL", publicSummary: "Nueva fecha validada por competición." })} type="button">Validar</button>
            <button disabled={disabled} onClick={() => void command("postponement.respond", leagueOperationalNumber(context.revision), { requestId: item.id, responseKind: "DENY", reasonCode: "ORGANIZER_DENIAL", publicSummary: "Cambio no autorizado por competición." })} type="button">Denegar</button>
          </> : null}
        </div> : null}
      </article>)}
      {!leagueOperationalArray(data.postponementRequests).length ? <p className={styles.empty}>No hay solicitudes.</p> : null}
    </div>
  </section>;
}

function IncidentList({ command, data, disabled }: { command: Command; data: LeagueOperationalJson; disabled: boolean }) {
  const context = leagueOperationalRecord(data.context);
  const manager = leagueOperationalBoolean(leagueOperationalRecord(data.permissions).manageOperations);
  const revision = leagueOperationalNumber(context.revision);
  return <section className={styles.listBand}>
    <SectionHeader eyebrow="Hechos reportados" title="Incidencias" />
    <div className={styles.itemGrid}>
      {leagueOperationalArray(data.lateArrivalIncidents).map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}>
        <header><strong>Retraso</strong>{statusChip(item.status)}</header>
        <small>Margen hasta {dateLabel(item.graceDeadline)}</small>
        {leagueOperationalText(item.status) === "reported" && (manager || managesEntry(data, item.responsibleEntryId)) ? <div className={styles.inlineActions}>
          <button disabled={disabled} onClick={() => void command("late_arrival.confirm_arrival", revision, { incidentId: item.id, reasonCode: "ARRIVAL_CONFIRMED" })} type="button">Ha llegado</button>
          {manager || managesEntry(data, leagueOperationalText(item.responsibleEntryId) === leagueOperationalText(context.homeEntryId) ? context.awayEntryId : context.homeEntryId) ? <button disabled={disabled} onClick={() => void command("late_arrival.escalate", revision, { incidentId: item.id, reasonCode: "GRACE_EXPIRED", reasonText: "No compareció tras el margen reglamentario.", publicSummary: "Incomparecencia en revisión." })} type="button">Escalar</button> : null}
        </div> : null}
      </article>)}
      {leagueOperationalArray(data.noShowIncidents).map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}>
        <header><strong>Incomparecencia</strong>{statusChip(item.status)}</header>
        <p>{leagueOperationalText(item.publicSummary) || leagueOperationalText(item.reasonCode)}</p>
        {manager && ["reported", "under_review"].includes(leagueOperationalText(item.status)) ? <div className={styles.inlineActions}>
          <button disabled={disabled} onClick={() => void command("no_show.confirm", revision, { incidentId: item.id, reasonCode: "NO_SHOW_CONFIRMED", reasonText: "Evidencia revisada por la autoridad.", publicSummary: "Incomparecencia confirmada." })} type="button">Confirmar</button>
          <button disabled={disabled} onClick={() => void command("no_show.reject", revision, { incidentId: item.id, reasonCode: "EVIDENCE_INSUFFICIENT", publicSummary: "Incidencia rechazada." })} type="button">Rechazar</button>
        </div> : null}
        {manager && leagueOperationalText(item.status) === "confirmed" ? <button disabled={disabled} onClick={() => void command("no_show.resolve", revision, { incidentId: item.id, reasonCode: "CASE_RESOLVED" })} type="button">Cerrar</button> : null}
      </article>)}
      {leagueOperationalArray(data.suspensions).map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}>
        <header><strong>Suspensión · min {leagueOperationalNumber(item.reportedMinute)}</strong>{statusChip(item.status)}</header>
        <p>{leagueOperationalNumber(item.sportingScoreHome)} - {leagueOperationalNumber(item.sportingScoreAway)} · {leagueOperationalText(item.publicSummary)}</p>
        <div className={styles.inlineActions}>
          {manager && leagueOperationalText(item.status) === "reported" ? <button disabled={disabled} onClick={() => void command("suspension.confirm", revision, { suspensionId: item.id, reasonCode: "SUSPENSION_CONFIRMED", reasonText: "Suspensión confirmada por la autoridad." })} type="button">Confirmar</button> : null}
          {manager && leagueOperationalText(item.status) === "resume_scheduled" ? <button disabled={disabled} onClick={() => void command("suspension.resume", revision, { suspensionId: item.id, reasonCode: "MATCH_RESUMED" })} type="button">Reanudar</button> : null}
        </div>
      </article>)}
      {!leagueOperationalArray(data.lateArrivalIncidents).length && !leagueOperationalArray(data.noShowIncidents).length && !leagueOperationalArray(data.suspensions).length ? <p className={styles.empty}>No hay incidencias operativas.</p> : null}
    </div>
  </section>;
}

function DecisionList({ data }: { data: LeagueOperationalJson }) {
  return <section className={styles.listBand}>
    <SectionHeader eyebrow="Autoridad" title="Decisiones administrativas" />
    <div className={styles.itemGrid}>
      {leagueOperationalArray(data.administrativeDecisions).map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}>
        <header>{statusChip(item.status)}<small>seq {leagueOperationalNumber(item.serverSequence)}</small></header>
        <strong>{leagueOperationalText(item.decisionType).replaceAll("_", " ")}</strong>
        <p>{leagueOperationalText(item.publicSummary) || leagueOperationalText(item.reasonCode)}</p>
        <small>{dateLabel(item.decidedAt)}</small>
      </article>)}
      {!leagueOperationalArray(data.administrativeDecisions).length ? <p className={styles.empty}>No hay decisiones publicadas.</p> : null}
    </div>
  </section>;
}

function MatchCommandDesk({ command, data, disabled }: { command: Command; data: LeagueOperationalJson; disabled: boolean }) {
  const context = leagueOperationalRecord(data.context);
  const permissions = leagueOperationalRecord(data.permissions);
  const manager = leagueOperationalBoolean(permissions.manageOperations);
  const manageHome = leagueOperationalBoolean(permissions.manageHome);
  const manageAway = leagueOperationalBoolean(permissions.manageAway);
  const teamActor = manageHome || manageAway;
  const homeEntryId = leagueOperationalText(context.homeEntryId);
  const awayEntryId = leagueOperationalText(context.awayEntryId);
  const actorEntryIds = [manageHome ? homeEntryId : "", manageAway ? awayEntryId : ""].filter(Boolean);
  const defaultActorEntryId = actorEntryIds[0] || homeEntryId;
  const defaultReportedEntryId = manager ? awayEntryId : defaultActorEntryId === homeEntryId ? awayEntryId : homeEntryId;
  const [reasonCode, setReasonCode] = useState("OTHER");
  const [publicSummary, setPublicSummary] = useState("");
  const [reasonText, setReasonText] = useState("");
  const [evidence, setEvidence] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [venue, setVenue] = useState("");
  const [minute, setMinute] = useState("1");
  const [partialScoreHome, setPartialScoreHome] = useState("0");
  const [partialScoreAway, setPartialScoreAway] = useState("0");
  const [entryId, setEntryId] = useState(defaultActorEntryId);
  const [reportedEntryId, setReportedEntryId] = useState(defaultReportedEntryId);
  const revision = leagueOperationalNumber(context.revision);
  const selectedActorEntryId = actorEntryIds.includes(entryId) ? entryId : defaultActorEntryId;
  const selectedReportedEntryId = !manager && reportedEntryId === selectedActorEntryId
    ? defaultReportedEntryId
    : reportedEntryId;
  const payload = commonPayload(reasonCode, publicSummary, reasonText, evidence);
  const canWrite = !disabled && (manager || teamActor);
  const iso = (value: string) => value ? new Date(value).toISOString() : "";
  const suspension = leagueOperationalArray(data.suspensions)[0] ?? {};
  const suspensionId = leagueOperationalText(suspension.id);
  const suspensionStatus = leagueOperationalText(suspension.status);

  return <section className={styles.commandBand}>
    <SectionHeader eyebrow="Intención versionada" title="Operar partido" />
    <div className={styles.formGrid}>
      <label>Código<select value={reasonCode} onChange={(event) => setReasonCode(event.target.value)}><option value="OTHER">Otro</option><option value="WEATHER">Tiempo</option><option value="PITCH_UNAVAILABLE">Campo no disponible</option><option value="SAFETY">Seguridad</option></select></label>
      <label>Resumen público<input maxLength={500} onChange={(event) => setPublicSummary(event.target.value)} value={publicSummary} /></label>
      <label>Detalle privado<textarea maxLength={4000} onChange={(event) => setReasonText(event.target.value)} rows={2} value={reasonText} /></label>
      <label>Evidencias privadas<input maxLength={16000} onChange={(event) => setEvidence(event.target.value)} placeholder="referencia-1, referencia-2" value={evidence} /></label>
      {teamActor ? <label>Equipo solicitante<select onChange={(event) => setEntryId(event.target.value)} value={selectedActorEntryId}>{manageHome ? <option value={homeEntryId}>Local</option> : null}{manageAway ? <option value={awayEntryId}>Visitante</option> : null}</select></label> : null}
      <label>Equipo reportado<select onChange={(event) => setReportedEntryId(event.target.value)} value={selectedReportedEntryId}><option value={homeEntryId}>Local</option><option value={awayEntryId}>Visitante</option></select></label>
      <label>Inicio<input onChange={(event) => setStart(event.target.value)} type="datetime-local" value={start} /></label>
      <label>Fin<input onChange={(event) => setEnd(event.target.value)} type="datetime-local" value={end} /></label>
      <label>Sede<input maxLength={160} onChange={(event) => setVenue(event.target.value)} value={venue} /></label>
      <label>Minuto<input max={180} min={0} onChange={(event) => setMinute(event.target.value)} type="number" value={minute} /></label>
      <label>Marcador local<input max={99} min={0} onChange={(event) => setPartialScoreHome(event.target.value)} type="number" value={partialScoreHome} /></label>
      <label>Marcador visitante<input max={99} min={0} onChange={(event) => setPartialScoreAway(event.target.value)} type="number" value={partialScoreAway} /></label>
    </div>
    <div className={styles.commandGroups}>
      {teamActor ? <div><strong>Equipo</strong><button disabled={!canWrite || !start || !end} onClick={() => void command("postponement.request", revision, { ...payload, proposedEnd: iso(end), proposedStart: iso(start), proposedTimezone: leagueOperationalText(context.timezone), requestingEntryId: selectedActorEntryId })} type="button">Solicitar aplazamiento</button><button disabled={!canWrite} onClick={() => void command("late_arrival.report", revision, { ...payload, responsibleEntryId: selectedReportedEntryId })} type="button">Reportar retraso rival</button><button disabled={!canWrite || !reasonText.trim()} onClick={() => void command("suspension.report", revision, { ...payload, partialScoreAway: Number(partialScoreAway), partialScoreHome: Number(partialScoreHome), reportedMinute: Number(minute), reportingEntryId: selectedActorEntryId })} type="button">Reportar suspensión</button></div> : null}
      {manager ? <div><strong>Organizador</strong><button disabled={!canWrite || !start || !end} onClick={() => void command("fixture.reschedule", revision, { ...payload, scheduledEnd: iso(end), scheduledStart: iso(start), timezone: leagueOperationalText(context.timezone) })} type="button">Reprogramar</button><button disabled={!canWrite || !venue} onClick={() => void command("fixture.change_venue", revision, { ...payload, venueLabel: venue, venueStatus: "LABEL" })} type="button">Cambiar sede</button><button disabled={!canWrite} onClick={() => void command("fixture.cancel", revision, { ...payload, cancellationOutcome: "NO_RESULT" })} type="button">Cancelar</button><button disabled={!canWrite || !reasonText.trim()} onClick={() => void command("no_show.report", revision, { ...payload, responsibleEntryId: selectedReportedEntryId })} type="button">Reportar no-show</button><button disabled={!canWrite || !reasonText.trim()} onClick={() => void command("suspension.report", revision, { ...payload, partialScoreAway: Number(partialScoreAway), partialScoreHome: Number(partialScoreHome), reportedMinute: Number(minute) })} type="button">Suspender</button>{suspensionStatus === "confirmed" ? <><button disabled={!canWrite || !start || !end} onClick={() => void command("suspension.schedule_resume", revision, { ...payload, resumeMinute: Number(minute), scheduledEnd: iso(end), scheduledStart: iso(start), suspensionId, timezone: leagueOperationalText(context.timezone), venueLabel: venue || undefined, venueStatus: venue ? "LABEL" : "TBD" })} type="button">Programar reanudación</button><button disabled={!canWrite || !start || !end} onClick={() => void command("suspension.order_replay", revision, { ...payload, scheduledEnd: iso(end), scheduledStart: iso(start), suspensionId, timezone: leagueOperationalText(context.timezone), venueLabel: venue || undefined, venueStatus: venue ? "LABEL" : "TBD" })} type="button">Ordenar repetición</button><button disabled={!canWrite} onClick={() => void command("suspension.resolve", revision, { ...payload, resolutionType: "PENDING_ADMINISTRATIVE_DECISION", suspensionId })} type="button">Elevar a decisión</button><button disabled={!canWrite} onClick={() => void command("suspension.cancel", revision, { ...payload, cancellationOutcome: "NO_RESULT", suspensionId })} type="button">Cancelar sin resultado</button></> : null}{suspensionStatus === "administrative_resolution" ? <button disabled={!canWrite} onClick={() => void command("administrative_decision.publish", revision, { ...payload, decisionType: "SET_OFFICIAL_RESULT", suspensionId })} type="button">Publicar resultado parcial</button> : null}</div> : null}
    </div>
  </section>;
}

function MatchView({ command, data, disabled }: { command: Command; data: LeagueOperationalJson; disabled: boolean }) {
  const flags = leagueOperationalRecord(data.flags);
  return <>
    <div className={styles.metrics}>
      <MetricTile label="Revisión" value={leagueOperationalNumber(data.revision)} />
      <MetricTile label="Secuencia" value={leagueOperationalNumber(data.serverSequence)} />
      <MetricTile label="Solicitudes" value={leagueOperationalArray(data.postponementRequests).length} />
      <MetricTile label="Incidencias" value={leagueOperationalArray(data.lateArrivalIncidents).length + leagueOperationalArray(data.noShowIncidents).length + leagueOperationalArray(data.suspensions).length} />
    </div>
    <MatchTimeline data={data} />
    <RequestList command={command} data={data} disabled={disabled || !leagueOperationalBoolean(flags.postponementsEnabled)} />
    <IncidentList command={command} data={data} disabled={disabled} />
    <DecisionList data={data} />
    <MatchCommandDesk command={command} data={data} disabled={disabled} />
  </>;
}

function RequestDesk({ data, mine = false }: { data: LeagueOperationalJson; mine?: boolean }) {
  const counts = leagueOperationalRecord(data.counts);
  const items = leagueOperationalArray(data.items);
  return <>
    {!mine ? <div className={styles.metrics}><MetricTile label="Pendientes" value={leagueOperationalNumber(counts.pending)} /><MetricTile label="Deadlines vencidos" value={leagueOperationalNumber(counts.expiredDeadlines)} /><MetricTile label="Aplazados" value={leagueOperationalNumber(counts.postponedMatches)} /></div> : null}
    <section className={styles.listBand}><SectionHeader eyebrow={mine ? "Equipos" : "Organizador"} title={mine ? "Mis solicitudes" : "Mesa de aplazamientos"} /><div className={styles.itemGrid}>{items.map((item) => {
      const requesting = leagueOperationalRecord(item.requestingEntry);
      const responding = leagueOperationalRecord(item.respondingEntry);
      return <article className={styles.item} key={leagueOperationalText(item.id)}><header>{statusChip(item.status)}<small>r{leagueOperationalNumber(item.revision)}</small></header><strong>{leagueOperationalText(requesting.name)} → {leagueOperationalText(responding.name)}</strong><p>{dateLabel(item.proposedStart, leagueOperationalText(item.proposedTimezone))}</p><small>{leagueOperationalText(item.publicSummary) || leagueOperationalText(item.reasonCode)}</small><Link href={`/competiciones/${leagueOperationalText(item.competitionId) || leagueOperationalText(data.competitionId)}/partidos/${leagueOperationalText(item.canonicalMatchId)}/operaciones`}>Ver operación</Link></article>;
    })}{!items.length ? <p className={styles.empty}>No hay solicitudes.</p> : null}</div></section>
  </>;
}

function IncidentDesk({ data }: { data: LeagueOperationalJson }) {
  const counts = leagueOperationalRecord(data.counts);
  const competitionId = leagueOperationalText(data.competitionId);
  const groups = [
    { items: leagueOperationalArray(data.lateArrivals), label: "Retrasos" },
    { items: leagueOperationalArray(data.noShows), label: "Incomparecencias" },
    { items: leagueOperationalArray(data.suspensions), label: "Suspensiones" },
  ];
  return <><div className={styles.metrics}><MetricTile label="Retrasos abiertos" value={leagueOperationalNumber(counts.lateArrivalOpen)} /><MetricTile label="No-show pendientes" value={leagueOperationalNumber(counts.noShowPending)} /><MetricTile label="Suspendidos" value={leagueOperationalNumber(counts.suspended)} /></div>{groups.map((group) => <section className={styles.listBand} key={group.label}><SectionHeader title={group.label} /><div className={styles.itemGrid}>{group.items.map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}><header>{statusChip(item.status)}<small>seq {leagueOperationalNumber(item.serverSequence)}</small></header><strong>{leagueOperationalText(leagueOperationalRecord(item.responsibleEntry).name) || `Minuto ${leagueOperationalNumber(item.reportedMinute)}`}</strong><p>{leagueOperationalText(item.publicSummary) || leagueOperationalText(item.reasonCode)}</p><Link href={`/competiciones/${competitionId}/partidos/${leagueOperationalText(item.canonicalMatchId)}/operaciones`}>Ver partido</Link></article>)}{!group.items.length ? <p className={styles.empty}>Sin casos.</p> : null}</div></section>)}</>;
}

function AdministrativeDesk({ data }: { data: LeagueOperationalJson }) {
  return <section className={styles.listBand}><SectionHeader eyebrow="Registro auditable" title="Decisiones administrativas" /><div className={styles.itemGrid}>{leagueOperationalArray(data.items).map((item) => <article className={styles.item} key={leagueOperationalText(item.id)}><header>{statusChip(item.status)}<small>seq {leagueOperationalNumber(item.serverSequence)}</small></header><strong>{leagueOperationalText(item.decisionType).replaceAll("_", " ")}</strong><p>{leagueOperationalText(item.publicSummary) || leagueOperationalText(item.reasonCode)}</p><small>{leagueOperationalArray(item.effects).map((effect) => leagueOperationalText(effect.type)).join(" · ") || "Sin efecto"}</small></article>)}{!leagueOperationalArray(data.items).length ? <p className={styles.empty}>No hay decisiones.</p> : null}</div></section>;
}

function PublicFixture({ data }: { data: LeagueOperationalJson }) {
  const original = leagueOperationalRecord(data.originalSchedule);
  const effective = leagueOperationalRecord(data.effectiveSchedule);
  const latest = leagueOperationalRecord(data.latestChange);
  return <section className={styles.publicStatus}><span>Estado oficial</span><h2>{leagueOperationalText(data.statusLabel) || "Programado"}</h2><div><p><strong>Original</strong>{dateLabel(original.scheduledStart, leagueOperationalText(original.timezone))}<small>{leagueOperationalText(original.venueLabel)}</small></p><p><strong>Actual</strong>{dateLabel(effective.scheduledStart, leagueOperationalText(effective.timezone))}<small>{leagueOperationalText(effective.venueLabel)}</small></p></div>{Object.keys(latest).length ? <footer>{leagueOperationalText(latest.summary) || leagueOperationalText(latest.reasonCode)}</footer> : null}</section>;
}

export function LeagueOperationalExceptionsClient(props: Props) {
  const { previewData = null, surface } = props;
  const endpoint = endpointFor(props);
  const identity = props.matchId || props.competitionId || surface;
  const [data, setData] = useState<LeagueOperationalJson | null>(previewData);
  const dataRef = useRef<LeagueOperationalJson | null>(previewData);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [online, setOnline] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(previewData ? "Escenario visual aislado" : "");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const setCanonical = useCallback((value: LeagueOperationalJson | null) => {
    dataRef.current = value;
    setData(value);
  }, []);

  const loadCanonical = useCallback(async (token: string, actorId: string, source: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch(endpoint, { cache: "no-store", headers: token ? { Authorization: `Bearer ${token}` } : undefined });
      const body = leagueOperationalRecord(await response.json());
      if (!response.ok) throw new Error(leagueOperationalText(body.message) || "No se pudo recuperar el estado canónico.");
      setCanonical(body);
      setCached(false);
      writeCache(cacheKey(surface, identity, actorId), surface, body);
      if (source === "realtime") setMessage("Estado actualizado desde PostgreSQL");
    } catch (error) {
      const cachedData = readCache(cacheKey(surface, identity, actorId));
      if (cachedData) {
        setCanonical(cachedData);
        setCached(true);
        setMessage("Sin conexión. Copia local de solo lectura.");
      } else {
        setMessage(error instanceof Error ? error.message : "No se pudo recuperar el estado canónico.");
      }
    } finally {
      setLoading(false);
    }
  }, [endpoint, identity, setCanonical, surface]);

  useEffect(() => {
    if (previewData) return;
    let active = true;
    let removeOnline: (() => void) | undefined;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const sessionResult = await supabase?.auth.getSession();
      if (!active) return;
      const token = sessionResult?.data.session?.access_token ?? "";
      const actorId = sessionResult?.data.session?.user.id ?? "";
      if (surface !== "public" && (!token || !actorId)) {
        setLoading(false);
        setMessage("Inicia sesión para consultar las operaciones de Liga.");
        return;
      }
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(cacheKey(surface, identity, actorId));
      if (local) { setCanonical(local); setCached(true); setLoading(false); }
      await loadCanonical(token, actorId, "initial");
      const reconcile = () => {
        setOnline(navigator.onLine);
        if (navigator.onLine) void loadCanonical(token, actorId, "realtime");
      };
      window.addEventListener("online", reconcile);
      window.addEventListener("offline", reconcile);
      removeOnline = () => { window.removeEventListener("online", reconcile); window.removeEventListener("offline", reconcile); };
      if (!supabase) return;
      channel = supabase.channel(`league-operational:${surface}:${identity}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: leagueOperationalExceptionsRealtimeTable }, (payload) => {
          if (!invalidationMatches(props, payload)) return;
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(token, actorId, "realtime"), 120);
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") void loadCanonical(token, actorId, "realtime");
        });
    };
    void start();
    return () => {
      active = false;
      removeOnline?.();
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  // Endpoint identity is the subscription contract; canonical payloads are refetched.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identity, loadCanonical, previewData, props.competitionId, props.matchId, setCanonical, surface]);

  const command: Command = useCallback(async (action, expectedRevision, payload = {}, aggregateOverride = "") => {
    if (previewData) { setMessage(`Laboratorio: ${leagueOperationalActionLabel(action)} no ha escrito datos.`); return; }
    if (!navigator.onLine) { setMessage("Sin conexión. La operación no se ha enviado ni confirmado."); return; }
    const context = leagueOperationalRecord(dataRef.current?.context);
    const aggregateId = aggregateOverride || leagueOperationalText(context.id);
    if (!accessToken || !aggregateId) { setMessage("No hay sesión o agregado canónico para esta operación."); return; }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:league-operational-exceptions-command", "/api/competitions/operational-exceptions/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = leagueOperationalRecord(await response.json());
      if (!response.ok) throw new Error(leagueOperationalText(body.message) || "Operación no confirmada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL");
      await loadCanonical(accessToken, userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Recuperando el estado oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
    } finally {
      setBusy(false);
    }
  }, [accessToken, loadCanonical, previewData, userId]);

  const title = useMemo(() => ({ decisions: "Decisiones de Liga", incidents: "Incidencias de Liga", match: "Operaciones del partido", my: "Mis solicitudes", postponements: "Aplazamientos", public: "Estado del partido" })[surface], [surface]);
  const flags = leagueOperationalRecord(data?.flags);
  const enabled = previewData ? true : surface === "public" ? Boolean(data) : leagueOperationalFlagsEnabled(flags);
  const shellContext = { detail: previewData ? "Laboratorio local" : cached ? "Copia local revalidándose" : "Snapshot canónico", eyebrow: "League Engine R4D", status: previewData ? "Solo visual" : loading ? "Sincronizando" : online ? "Servidor" : "Sin conexión", title };

  return <OfficialProductShellV2 active={surface === "my" ? "equipo" : "partido"} context={shellContext}>
    <main className={styles.page} data-mobile-tab={surface === "my" ? "equipo" : "partido"} data-operational-surface={surface}>
      <GamePageHeader eyebrow="Excepciones operativas" title={title} />
      {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /sin conexión|no |error|rechaz|inicia|revision/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
      {loading && !data ? <ProductState busy description="Recuperando la última revisión confirmada." eyebrow="PostgreSQL" surface="dark" title="Sincronizando" /> : null}
      {!loading && !data ? <ProductState description="La superficie no está disponible para este contexto o usuario." eyebrow="Acceso" surface="dark" title="Sin estado operativo" /> : null}
      {data && !enabled ? <ProductState description="La autoridad R4D está desplegada, pero sus acciones permanecen desactivadas." eyebrow="Feature flag" surface="dark" title="Operaciones de Liga inactivas" /> : null}
      {data && enabled && surface === "match" ? <MatchView command={command} data={data} disabled={busy || !online} /> : null}
      {data && enabled && surface === "postponements" ? <RequestDesk data={data} /> : null}
      {data && enabled && surface === "incidents" ? <IncidentDesk data={data} /> : null}
      {data && enabled && surface === "decisions" ? <AdministrativeDesk data={data} /> : null}
      {data && enabled && surface === "my" ? <RequestDesk data={data} mine /> : null}
      {data && enabled && surface === "public" ? <PublicFixture data={data} /> : null}
    </main>
  </OfficialProductShellV2>;
}
