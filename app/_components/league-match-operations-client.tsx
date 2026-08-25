"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  leagueMatchActionLabel,
  leagueMatchArray,
  leagueMatchBoolean,
  leagueMatchNumber,
  leagueMatchOperationsCacheVersion,
  leagueMatchOperationsRealtimeTable,
  leagueMatchRecord,
  leagueMatchStatusTone,
  leagueMatchText,
  type LeagueMatchOperationsAction,
  type LeagueMatchOperationsJson,
} from "../league-match-operations-contract";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  ResponsiveActionBar,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import { CompetitionDisciplineClient } from "./competition-discipline-client";
import type { CompetitionDisciplineJson } from "../competition-discipline-contract";
import styles from "./league-match-operations-client.module.css";

export type LeagueMatchOperationsSurface = "match" | "my" | "results" | "standings";

type Props = {
  competitionId?: string;
  disciplinePreviewData?: CompetitionDisciplineJson | null;
  divisionId?: string;
  embedded?: boolean;
  groupId?: string;
  matchId?: string;
  previewData?: LeagueMatchOperationsJson | null;
  publicView?: boolean;
  stageId?: string;
  surface: LeagueMatchOperationsSurface;
};

type Command = (
  action: LeagueMatchOperationsAction,
  expectedRevision: number,
  payload?: LeagueMatchOperationsJson,
  aggregateOverride?: string,
) => Promise<void>;

function endpointFor(props: Props) {
  if (props.surface === "match") {
    return `/api/competitions/match-operations/match/${props.competitionId ?? ""}/${props.matchId ?? ""}`;
  }
  if (props.surface === "results") {
    return `/api/competitions/match-operations/results/${props.competitionId ?? ""}`;
  }
  if (props.surface === "standings") {
    const query = new URLSearchParams();
    if (props.stageId) query.set("stage", props.stageId);
    if (props.divisionId) query.set("division", props.divisionId);
    if (props.groupId) query.set("group", props.groupId);
    if (props.publicView) query.set("public", "1");
    return `/api/competitions/match-operations/standings/${props.competitionId ?? ""}?${query}`;
  }
  return "/api/competitions/match-operations/my";
}

function identityFor(props: Props) {
  return props.matchId || props.stageId || props.competitionId || props.surface;
}

function cacheKey(surface: LeagueMatchOperationsSurface, identity: string, userId: string) {
  return `pachangas-league-match-operations-read-v1:${surface}:${identity}:${userId || "public"}`;
}

function cacheLifetime(surface: LeagueMatchOperationsSurface, data: LeagueMatchOperationsJson) {
  if (surface === "match" && leagueMatchText(leagueMatchRecord(data.context).status) === "official") return 7 * 24 * 60 * 60 * 1000;
  if (surface === "standings") return 30 * 60 * 1000;
  return 5 * 60 * 1000;
}

function readCache(key: string) {
  try {
    const envelope = leagueMatchRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (leagueMatchNumber(envelope.version) !== leagueMatchOperationsCacheVersion) return null;
    if (Date.now() > leagueMatchNumber(envelope.expiresAt)) return null;
    return leagueMatchRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, surface: LeagueMatchOperationsSurface, data: LeagueMatchOperationsJson) {
  try {
    window.localStorage.setItem(key, JSON.stringify({
      data,
      expiresAt: Date.now() + cacheLifetime(surface, data),
      storedAt: new Date().toISOString(),
      version: leagueMatchOperationsCacheVersion,
    }));
  } catch {
    // This read cache is optional and never authoritative.
  }
}

function displayName(value: unknown, fallback = "Jugador") {
  const record = leagueMatchRecord(value);
  return leagueMatchText(record.displayName) || leagueMatchText(record.name) || fallback;
}

function dateLabel(value: unknown, timezone = "Europe/Madrid") {
  const parsed = new Date(leagueMatchText(value));
  if (Number.isNaN(parsed.getTime())) return "Horario pendiente";
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone || "Europe/Madrid",
  }).format(parsed);
}

function statusChip(value: unknown) {
  const text = leagueMatchText(value).replaceAll("_", " ") || "pendiente";
  return <StatusChip tone={leagueMatchStatusTone(value)}>{text}</StatusChip>;
}

function invalidationMatches(props: Props, data: LeagueMatchOperationsJson | null, payload: unknown) {
  const row = leagueMatchRecord(leagueMatchRecord(payload).new);
  const entityType = leagueMatchText(row.entity_type);
  if (entityType === "league_match_operations_flags") return true;
  if (props.competitionId && leagueMatchText(row.competition_id) !== props.competitionId) return false;
  if (props.surface === "my") return ["match", "result", "round", "squad", "standings"].includes(entityType);
  const entityId = leagueMatchText(row.entity_id);
  if (props.surface === "standings") return entityType === "standings" && entityId === props.stageId;
  if (props.surface === "results") return ["match", "result", "round", "standings"].includes(entityType);
  const context = leagueMatchRecord(data?.context);
  return entityId === leagueMatchText(context.id)
    || entityId === leagueMatchText(context.canonicalMatchId)
    || entityId === leagueMatchText(context.roundId)
    || ["match", "result", "round", "squad", "standings"].includes(entityType);
}

function flagEnabled(data: LeagueMatchOperationsJson | null) {
  return leagueMatchBoolean(leagueMatchRecord(data?.flags).foundationEnabled);
}

function MatchScoreboard({ data }: { data: LeagueMatchOperationsJson }) {
  const context = leagueMatchRecord(data.context);
  const home = leagueMatchRecord(data.homeEntry);
  const away = leagueMatchRecord(data.awayEntry);
  const sporting = leagueMatchRecord(data.sportingResult);
  const official = leagueMatchRecord(data.officialResult);
  const hasScore = Object.keys(official).length > 0 || Object.keys(sporting).length > 0;
  const source = Object.keys(official).length ? official : sporting;
  return <section className={styles.scoreboard}>
    <div className={styles.scoreContext}>
      <span>{leagueMatchText(leagueMatchRecord(data.competition).name) || "Liga"}</span>
      <strong>{leagueMatchText(leagueMatchRecord(data.round).name) || "Partido de Liga"}</strong>
      <small>{dateLabel(context.scheduledStart, leagueMatchText(context.timezone))}</small>
    </div>
    <div className={styles.teamName} data-side="home"><strong>{leagueMatchText(home.name) || "Local"}</strong><small>LOCAL</small></div>
    <div className={styles.score}>
      <strong>{hasScore ? `${leagueMatchNumber(source.scoreHome)} · ${leagueMatchNumber(source.scoreAway)}` : "VS"}</strong>
      {statusChip(leagueMatchText(official.outcome) || context.status)}
    </div>
    <div className={styles.teamName} data-side="away"><strong>{leagueMatchText(away.name) || "Visitante"}</strong><small>VISITANTE</small></div>
    <div className={styles.venue}><span>{leagueMatchText(context.venueLabel) || "Sede pendiente"}</span><small>Disciplina: no disponible hasta R5</small></div>
  </section>;
}

function MatchOverview({ data }: { data: LeagueMatchOperationsJson }) {
  const context = leagueMatchRecord(data.context);
  const round = leagueMatchRecord(data.round);
  const competition = leagueMatchRecord(data.competition);
  const edition = leagueMatchRecord(data.edition);
  const stage = leagueMatchRecord(data.stage);
  const rule = leagueMatchRecord(data.ruleRevision);
  return <section className={styles.surfaceBand}>
    <SectionHeader eyebrow="Contexto canónico" title="Partido publicado" />
    <dl className={styles.detailGrid}>
      <div><dt>Competición</dt><dd>{leagueMatchText(competition.name)}</dd></div>
      <div><dt>Temporada</dt><dd>{leagueMatchText(edition.seasonLabel) || leagueMatchText(edition.name)}</dd></div>
      <div><dt>Fase</dt><dd>{leagueMatchText(stage.name)}</dd></div>
      <div><dt>Jornada</dt><dd>{leagueMatchText(round.name) || leagueMatchNumber(round.number)}</dd></div>
      <div><dt>Estado</dt><dd>{statusChip(context.status)}</dd></div>
      <div><dt>Reglamento</dt><dd>v{leagueMatchNumber(rule.version)} · {leagueMatchText(rule.status)}</dd></div>
    </dl>
  </section>;
}

function AttendancePanel({ command, data, busy }: { busy: boolean; command: Command; data: LeagueMatchOperationsJson }) {
  const context = leagueMatchRecord(data.context);
  const permissions = leagueMatchRecord(data.permissions);
  const attendance = leagueMatchRecord(data.attendance);
  const home = leagueMatchRecord(data.homeEntry);
  const away = leagueMatchRecord(data.awayEntry);
  const eligible = leagueMatchRecord(data.eligibleRoster);
  const attendanceRows = leagueMatchArray(attendance.players);
  const byMember = new Map(attendanceRows.map((item) => [leagueMatchText(item.rosterMemberId), item]));
  const actorProfileId = leagueMatchText(permissions.actorPlayerProfileId);
  const sides = [
    { closed: attendance.homeClosedAt, entry: home, key: "home", manage: leagueMatchBoolean(permissions.manageHome), roster: leagueMatchArray(eligible.home) },
    { closed: attendance.awayClosedAt, entry: away, key: "away", manage: leagueMatchBoolean(permissions.manageAway), roster: leagueMatchArray(eligible.away) },
  ];
  return <section className={styles.surfaceBand}>
    <SectionHeader eyebrow="Attendance canónica" title="Disponibilidad" />
    <div className={styles.twoColumns}>{sides.map((side) => <section className={styles.teamPanel} key={side.key}>
      <header><div><strong>{leagueMatchText(side.entry.name)}</strong><small>{side.roster.length} elegibles</small></div>{side.closed ? statusChip("locked") : statusChip("open")}</header>
      <div className={styles.playerRows}>{side.roster.map((member) => {
        const current = byMember.get(leagueMatchText(member.rosterMemberId));
        const canEdit = !side.closed && (side.manage || actorProfileId === leagueMatchText(member.playerProfileId));
        return <article key={leagueMatchText(member.rosterMemberId)}>
          <span><strong>{displayName(member.player)}</strong><small>{leagueMatchText(member.eligibilityStatus)}</small></span>
          {canEdit ? <select
            aria-label={`Asistencia de ${displayName(member.player)}`}
            disabled={busy}
            onChange={(event) => void command("attendance.set", leagueMatchNumber(data.revision), {
              entryId: leagueMatchText(side.entry.id),
              rosterMemberId: leagueMatchText(member.rosterMemberId),
              status: event.target.value,
            })}
            value={leagueMatchText(current?.status) || "pending"}
          ><option value="going">Voy</option><option value="pending">Pendiente</option><option value="not_going">No voy</option></select> : statusChip(current?.status || "pending")}
        </article>;
      })}{!side.roster.length ? <p className={styles.empty}>No hay roster elegible.</p> : null}</div>
      {side.manage && !side.closed ? <button className={styles.secondaryButton} disabled={busy} onClick={() => void command("attendance.close", leagueMatchNumber(data.revision), { entryId: leagueMatchText(side.entry.id) })} type="button">Cerrar asistencia</button> : null}
    </section>)}</div>
    {leagueMatchText(context.status) !== "scheduled" ? <p className={styles.inlineNote}>La asistencia queda congelada al preparar el partido.</p> : null}
  </section>;
}

function SquadPanel({
  busy,
  command,
  data,
  memberRole,
  rosterSelection,
  setMemberRole,
  setRosterSelection,
}: {
  busy: boolean;
  command: Command;
  data: LeagueMatchOperationsJson;
  memberRole: Record<string, string>;
  rosterSelection: Record<string, string>;
  setMemberRole: (value: Record<string, string>) => void;
  setRosterSelection: (value: Record<string, string>) => void;
}) {
  const permissions = leagueMatchRecord(data.permissions);
  const eligible = leagueMatchRecord(data.eligibleRoster);
  const squads = leagueMatchArray(data.squads);
  const entries = [
    { entry: leagueMatchRecord(data.homeEntry), key: "home", manage: leagueMatchBoolean(permissions.manageHome), roster: leagueMatchArray(eligible.home), side: "HOME" },
    { entry: leagueMatchRecord(data.awayEntry), key: "away", manage: leagueMatchBoolean(permissions.manageAway), roster: leagueMatchArray(eligible.away), side: "AWAY" },
  ];
  const resultManager = leagueMatchBoolean(permissions.manageResults);
  return <section className={styles.surfaceBand}>
    <SectionHeader eyebrow="Revisión inmutable" title="Convocatorias y alineación" />
    <div className={styles.twoColumns}>{entries.map((item) => {
      const squad = squads.find((candidate) => leagueMatchText(candidate.entryId) === leagueMatchText(item.entry.id));
      const squadId = leagueMatchText(squad?.id);
      const members = leagueMatchArray(squad?.members);
      const used = new Set(members.map((member) => leagueMatchText(member.rosterMemberId)));
      const available = item.roster.filter((member) => !used.has(leagueMatchText(member.rosterMemberId)));
      const editable = item.manage && ["draft", "rejected"].includes(leagueMatchText(squad?.status));
      const selected = rosterSelection[squadId] || leagueMatchText(available[0]?.rosterMemberId);
      return <section className={styles.teamPanel} key={item.key}>
        <header><div><strong>{leagueMatchText(item.entry.name)}</strong><small>{item.side}</small></div>{statusChip(squad?.status || "not_created")}</header>
        {!squad && item.manage ? <button className={styles.primaryButton} disabled={busy} onClick={() => void command("squad.create", leagueMatchNumber(data.revision), { entryId: leagueMatchText(item.entry.id) })} type="button">Crear convocatoria</button> : null}
        <div className={styles.playerRows}>{members.map((member) => <article key={leagueMatchText(member.rosterMemberId)}>
          <span><strong>{displayName(member.player)}</strong><small>{leagueMatchText(member.role)}{leagueMatchBoolean(member.captain) ? " · capitán" : ""}</small></span>
          {editable ? <button aria-label={`Quitar ${displayName(member.player)}`} disabled={busy} onClick={() => void command("squad.member.remove", leagueMatchNumber(data.revision), { rosterMemberId: leagueMatchText(member.rosterMemberId), squadId })} type="button">Quitar</button> : null}
        </article>)}{squad && !members.length ? <p className={styles.empty}>Convocatoria vacía.</p> : null}</div>
        {editable && available.length ? <div className={styles.inlineForm}>
          <select aria-label={`Jugador para ${leagueMatchText(item.entry.name)}`} onChange={(event) => setRosterSelection({ ...rosterSelection, [squadId]: event.target.value })} value={selected}>{available.map((member) => <option key={leagueMatchText(member.rosterMemberId)} value={leagueMatchText(member.rosterMemberId)}>{displayName(member.player)}</option>)}</select>
          <select aria-label="Rol en la alineación" onChange={(event) => setMemberRole({ ...memberRole, [squadId]: event.target.value })} value={memberRole[squadId] || "STARTER"}><option value="STARTER">Titular</option><option value="SUBSTITUTE">Suplente</option></select>
          <button disabled={busy || !selected} onClick={() => void command("squad.member.add", leagueMatchNumber(data.revision), { memberRole: memberRole[squadId] || "STARTER", positionOrder: members.length, rosterMemberId: selected, squadId })} type="button">Añadir</button>
        </div> : null}
        {editable && members.length ? <button className={styles.primaryButton} disabled={busy} onClick={() => void command("squad.submit", leagueMatchNumber(data.revision), { squadId })} type="button">Enviar convocatoria</button> : null}
        {resultManager && leagueMatchText(squad?.status) === "submitted" ? <ResponsiveActionBar><button disabled={busy} onClick={() => void command("squad.validate", leagueMatchNumber(data.revision), { squadId })} type="button">Validar</button><button disabled={busy} onClick={() => void command("squad.reject", leagueMatchNumber(data.revision), { reason: "Convocatoria requiere correcciones", squadId })} type="button">Rechazar</button></ResponsiveActionBar> : null}
        {resultManager && leagueMatchText(squad?.status) === "validated" ? <button className={styles.primaryButton} disabled={busy} onClick={() => void command("squad.lock", leagueMatchNumber(data.revision), { squadId })} type="button">Bloquear alineación</button> : null}
      </section>;
    })}</div>
  </section>;
}

function ResultPanel({
  actingEntryId,
  busy,
  command,
  data,
  evidence,
  explanation,
  reason,
  scoreAway,
  scoreHome,
  scorerGoals,
  setActingEntryId,
  setEvidence,
  setExplanation,
  setReason,
  setScoreAway,
  setScoreHome,
  setScorerGoals,
}: {
  actingEntryId: string;
  busy: boolean;
  command: Command;
  data: LeagueMatchOperationsJson;
  evidence: string;
  explanation: string;
  reason: string;
  scoreAway: string;
  scoreHome: string;
  scorerGoals: Record<string, number>;
  setActingEntryId: (value: string) => void;
  setEvidence: (value: string) => void;
  setExplanation: (value: string) => void;
  setReason: (value: string) => void;
  setScoreAway: (value: string) => void;
  setScoreHome: (value: string) => void;
  setScorerGoals: (value: Record<string, number>) => void;
}) {
  const context = leagueMatchRecord(data.context);
  const permissions = leagueMatchRecord(data.permissions);
  const home = leagueMatchRecord(data.homeEntry);
  const away = leagueMatchRecord(data.awayEntry);
  const result = leagueMatchRecord(data.sportingResult);
  const official = leagueMatchRecord(data.officialResult);
  const squads = leagueMatchArray(data.squads);
  const manageable = [
    ...(leagueMatchBoolean(permissions.manageHome) ? [home] : []),
    ...(leagueMatchBoolean(permissions.manageAway) ? [away] : []),
  ];
  const pendingEntryId = leagueMatchText(result.pendingResponseFromEntryId);
  const responseAllowed = manageable.some((entry) => leagueMatchText(entry.id) === pendingEntryId);
  const effectiveEntryId = responseAllowed ? pendingEntryId : actingEntryId || leagueMatchText(manageable[0]?.id);
  const selectedSquad = squads.find((squad) => leagueMatchText(squad.entryId) === effectiveEntryId);
  const selectedMembers = leagueMatchArray(selectedSquad?.members);
  const scorers = selectedMembers.flatMap((member) => {
    const goals = scorerGoals[`${effectiveEntryId}:${leagueMatchText(member.rosterMemberId)}`] || 0;
    return goals > 0 ? [{ goals, rosterMemberId: leagueMatchText(member.rosterMemberId) }] : [];
  });
  const scorePayload = { entryId: effectiveEntryId, scoreAway: Number(scoreAway), scoreHome: Number(scoreHome), scorers };
  const nextActions = new Set(Array.isArray(data.nextValidActions) ? data.nextValidActions.map(leagueMatchText) : []);
  return <section className={styles.resultLayout}>
    <section className={styles.surfaceBand}>
      <SectionHeader eyebrow="Marcador versionado" title={Object.keys(official).length ? "Resultado oficial" : Object.keys(result).length ? "Resultado deportivo" : "Registrar resultado"} />
      <div className={styles.resultScore}><span>{leagueMatchText(home.name)}</span><strong>{Object.keys(result).length ? leagueMatchNumber(result.scoreHome) : "–"}</strong><i>:</i><strong>{Object.keys(result).length ? leagueMatchNumber(result.scoreAway) : "–"}</strong><span>{leagueMatchText(away.name)}</span></div>
      {Object.keys(official).length ? <p className={styles.officialDecision}>{statusChip(official.outcome)} <span>{leagueMatchText(official.publicExplanation) || "Decisión oficial vigente"}</span></p> : null}
      {Object.keys(result).length ? <div className={styles.resultMeta}>{statusChip(result.state)}<span>Respuesta hasta {dateLabel(result.responseDeadline)}</span><small>{leagueMatchText(result.confirmationPolicy)}</small></div> : null}
      {manageable.length && !Object.keys(result).length && nextActions.has("sporting_result.submit") ? <div className={styles.resultForm}>
        <label>Equipo que envía<select onChange={(event) => setActingEntryId(event.target.value)} value={effectiveEntryId}>{manageable.map((entry) => <option key={leagueMatchText(entry.id)} value={leagueMatchText(entry.id)}>{leagueMatchText(entry.name)}</option>)}</select></label>
        <label>Local<input inputMode="numeric" min="0" onChange={(event) => setScoreHome(event.target.value)} type="number" value={scoreHome} /></label>
        <label>Visitante<input inputMode="numeric" min="0" onChange={(event) => setScoreAway(event.target.value)} type="number" value={scoreAway} /></label>
        <button className={styles.primaryButton} disabled={busy || !effectiveEntryId || scoreHome === "" || scoreAway === ""} onClick={() => void command("sporting_result.submit", leagueMatchNumber(data.revision), scorePayload)} type="button">Enviar resultado</button>
      </div> : null}
      {responseAllowed && ["submitted", "change_proposed"].includes(leagueMatchText(result.state)) ? <div className={styles.resultForm}>
        <label>Local<input inputMode="numeric" min="0" onChange={(event) => setScoreHome(event.target.value)} type="number" value={scoreHome} /></label>
        <label>Visitante<input inputMode="numeric" min="0" onChange={(event) => setScoreAway(event.target.value)} type="number" value={scoreAway} /></label>
        <label className={styles.wideField}>Motivo<textarea onChange={(event) => setReason(event.target.value)} rows={2} value={reason} /></label>
        <ResponsiveActionBar><button disabled={busy} onClick={() => void command("sporting_result.accept", leagueMatchNumber(data.revision), { entryId: effectiveEntryId, scorers })} type="button">Aceptar</button><button disabled={busy} onClick={() => void command("sporting_result.propose_change", leagueMatchNumber(data.revision), { ...scorePayload, reason })} type="button">Proponer cambio</button><button disabled={busy} onClick={() => void command("sporting_result.dispute", leagueMatchNumber(data.revision), { ...scorePayload, reason })} type="button">Disputar</button></ResponsiveActionBar>
      </div> : null}
    </section>
    <aside className={styles.surfaceBand}>
      <SectionHeader eyebrow="Detalle propio" title="Goleadores" />
      <div className={styles.scorerRows}>{selectedMembers.map((member) => {
        const key = `${effectiveEntryId}:${leagueMatchText(member.rosterMemberId)}`;
        return <label key={key}><span>{displayName(member.player)}</span><input inputMode="numeric" min="0" onChange={(event) => setScorerGoals({ ...scorerGoals, [key]: Math.max(0, Number(event.target.value) || 0) })} type="number" value={scorerGoals[key] || 0} /></label>;
      })}{!selectedMembers.length ? <p className={styles.empty}>La alineación bloqueada habilitará el detalle de goleadores.</p> : null}</div>
      {leagueMatchArray(result.responses).length ? <div className={styles.responseHistory}>{leagueMatchArray(result.responses).map((response, index) => <p key={`${leagueMatchText(response.entryId)}-${index}`}><strong>{leagueMatchText(response.kind)}</strong><span>{dateLabel(response.createdAt)}</span></p>)}</div> : null}
    </aside>
    {leagueMatchBoolean(permissions.manageResults) && Object.keys(result).length ? <section className={`${styles.surfaceBand} ${styles.adminDecision}`}>
      <SectionHeader eyebrow="Autoridad de competición" title="Decisión oficial" />
      <div className={styles.resultForm}>
        <label>Marcador local<input inputMode="numeric" min="0" onChange={(event) => setScoreHome(event.target.value)} type="number" value={scoreHome} /></label>
        <label>Marcador visitante<input inputMode="numeric" min="0" onChange={(event) => setScoreAway(event.target.value)} type="number" value={scoreAway} /></label>
        <label className={styles.wideField}>Explicación pública<textarea onChange={(event) => setExplanation(event.target.value)} rows={2} value={explanation} /></label>
        <label className={styles.wideField}>Evidencia privada<textarea onChange={(event) => setEvidence(event.target.value)} rows={2} value={evidence} /></label>
        <ResponsiveActionBar><button disabled={busy} onClick={() => void command(Object.keys(official).length ? "official_result.supersede" : "official_result.publish", leagueMatchNumber(data.revision), { outcome: Object.keys(official).length ? "CORRECTED_EFFECTIVE_SCORE" : leagueMatchText(result.state) === "disputed" ? "CORRECTED_EFFECTIVE_SCORE" : "MIRROR_SPORTING_RESULT", privateEvidence: { privateReason: evidence }, publicExplanation: explanation, reasonCode: "result.organizer_decision", scoreAway: Number(scoreAway), scoreHome: Number(scoreHome) })} type="button">{Object.keys(official).length ? "Publicar corrección" : "Oficializar"}</button>{Object.keys(official).length ? <button disabled={busy} onClick={() => void command("official_result.annul", leagueMatchNumber(data.revision), { publicExplanation: explanation, reasonCode: "result.annulled" })} type="button">Anular</button> : null}</ResponsiveActionBar>
      </div>
    </section> : null}
    {leagueMatchBoolean(permissions.manageResults) ? <section className={`${styles.surfaceBand} ${styles.lifecycle}`}><SectionHeader eyebrow="Estado explícito" title="Operación del partido" /><ResponsiveActionBar>{(["match.mark_ready", "match.start", "match.mark_played"] as LeagueMatchOperationsAction[]).filter((action) => nextActions.has(action)).map((action) => <button disabled={busy} key={action} onClick={() => void command(action, leagueMatchNumber(data.revision))} type="button">{leagueMatchActionLabel(action)}</button>)}{leagueMatchText(context.status) === "official" ? <button disabled={busy} onClick={() => void command("round.complete", leagueMatchNumber(leagueMatchRecord(data.round).revision), {}, leagueMatchText(leagueMatchRecord(data.round).id))} type="button">Completar jornada</button> : null}</ResponsiveActionBar></section> : null}
  </section>;
}

function StandingsView({ data }: { data: LeagueMatchOperationsJson }) {
  const snapshot = leagueMatchRecord(data.snapshot);
  const rows = leagueMatchArray(snapshot.rows);
  const explanations = leagueMatchArray(snapshot.explanations);
  return <>
    <section className={styles.metrics} aria-label="Estado de la clasificación"><MetricTile label="Equipos" value={rows.length} /><MetricTile label="Resultados" value={leagueMatchNumber(snapshot.computedResults)} /><MetricTile label="Revisión" value={leagueMatchNumber(data.revision)} /><MetricTile label="Salud" value={statusChip(data.health)} /></section>
    <section className={styles.standingsBand}>
      <SectionHeader eyebrow="Tabla materializada" title="Clasificación" />
      {rows.length ? <div className={styles.tableScroll}><table><thead><tr><th>Pos</th><th>Equipo</th><th>PJ</th><th>G</th><th>E</th><th>P</th><th>GF</th><th>GC</th><th>DG</th><th>PTS</th></tr></thead><tbody>{rows.map((row) => <tr key={leagueMatchText(row.entryId)}><td><strong>{leagueMatchNumber(row.position)}</strong></td><td>{displayName(row.team, leagueMatchText(row.entryId))}</td><td>{leagueMatchNumber(row.played)}</td><td>{leagueMatchNumber(row.wins)}</td><td>{leagueMatchNumber(row.draws)}</td><td>{leagueMatchNumber(row.losses)}</td><td>{leagueMatchNumber(row.goalsFor)}</td><td>{leagueMatchNumber(row.goalsAgainst)}</td><td>{leagueMatchNumber(row.goalDifference)}</td><td><strong>{leagueMatchNumber(row.effectivePoints)}</strong></td></tr>)}</tbody></table></div> : <p className={styles.empty}>Aún no hay resultados oficiales computados.</p>}
    </section>
    <section className={styles.surfaceBand}><SectionHeader eyebrow="Reglamento congelado" title="Criterios de desempate" /><div className={styles.criteria}>{Array.isArray(snapshot.criteria) ? snapshot.criteria.map((item, index) => <span key={`${item}-${index}`}>{String(item).replaceAll("_", " ")}</span>) : null}</div>{explanations.map((item, index) => <p className={styles.explanation} key={`${leagueMatchText(item.tieGroupKey)}-${index}`}><strong>{leagueMatchText(item.criterion)}</strong><span>{leagueMatchText(item.explanation)}</span></p>)}</section>
  </>;
}

function ResultDesk({ competitionId, data }: { competitionId: string; data: LeagueMatchOperationsJson }) {
  const matches = leagueMatchArray(data.matches);
  return <section className={styles.surfaceBand}><SectionHeader eyebrow="Organizador" title="Mesa de resultados" /><div className={styles.resultDesk}>{matches.map((match) => <Link href={`/competiciones/${competitionId}/partidos/${leagueMatchText(match.canonicalMatchId)}`} key={leagueMatchText(match.contextId)}><span>{leagueMatchText(leagueMatchRecord(match.homeEntry).name)} <i>vs</i> {leagueMatchText(leagueMatchRecord(match.awayEntry).name)}</span><strong>{match.scoreHome == null ? "–" : `${leagueMatchNumber(match.scoreHome)} : ${leagueMatchNumber(match.scoreAway)}`}</strong><small>{leagueMatchText(match.roundName)} · {dateLabel(match.scheduledStart)}</small><em>{statusChip(match.sportingState || match.matchStatus)}</em><b>{leagueMatchActionLabel(leagueMatchText(match.nextAction))}</b></Link>)}{!matches.length ? <p className={styles.empty}>No hay partidos en esta cola.</p> : null}</div></section>;
}

function MyMatchOperations({ data }: { data: LeagueMatchOperationsJson }) {
  const matches = leagueMatchArray(data.matches);
  const standings = leagueMatchArray(data.standings);
  return <>
    <section className={styles.surfaceBand}><SectionHeader eyebrow="Mis competiciones" title="Partidos operables" /><div className={styles.myMatches}>{matches.map((match) => {
      const context = leagueMatchRecord(match.context);
      const official = leagueMatchRecord(match.officialResult);
      return <Link href={`/competiciones/${leagueMatchText(context.competitionId)}/partidos/${leagueMatchText(context.canonicalMatchId)}`} key={leagueMatchText(context.id)}><small>{leagueMatchText(leagueMatchRecord(match.round).name)} · {dateLabel(context.scheduledStart)}</small><strong>{leagueMatchText(leagueMatchRecord(match.homeEntry).name)} <i>vs</i> {leagueMatchText(leagueMatchRecord(match.awayEntry).name)}</strong><span>{Object.keys(official).length ? `${leagueMatchNumber(official.scoreHome)} : ${leagueMatchNumber(official.scoreAway)}` : leagueMatchText(context.status)}</span></Link>;
    })}{!matches.length ? <p className={styles.empty}>No tienes partidos de Liga operables.</p> : null}</div></section>
    {standings.map((standing) => <StandingsView data={standing} key={leagueMatchText(standing.standingStateId)} />)}
  </>;
}

export function LeagueMatchOperationsClient(props: Props) {
  const { competitionId = "", embedded = false, previewData = null, surface } = props;
  const endpoint = endpointFor(props);
  const identity = identityFor(props);
  const [data, setData] = useState<LeagueMatchOperationsJson | null>(previewData);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(previewData ? "Escenario visual aislado" : "");
  const [activeSection, setActiveSection] = useState("resumen");
  const [actingEntryId, setActingEntryId] = useState("");
  const [scoreHome, setScoreHome] = useState("0");
  const [scoreAway, setScoreAway] = useState("0");
  const [reason, setReason] = useState("");
  const [explanation, setExplanation] = useState("");
  const [evidence, setEvidence] = useState("");
  const [scorerGoals, setScorerGoals] = useState<Record<string, number>>({});
  const [rosterSelection, setRosterSelection] = useState<Record<string, string>>({});
  const [memberRole, setMemberRole] = useState<Record<string, string>>({});
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (token: string, actorId: string, source: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch(endpoint, { cache: "no-store", headers: token ? { Authorization: `Bearer ${token}` } : undefined });
      const body = leagueMatchRecord(await response.json());
      if (!response.ok) throw new Error(leagueMatchText(body.message) || "No se pudo recuperar el estado canónico.");
      setData(body);
      setCached(false);
      writeCache(cacheKey(surface, identity, actorId), surface, body);
      const result = leagueMatchRecord(body.sportingResult);
      if (Object.keys(result).length) {
        setScoreHome(String(leagueMatchNumber(result.scoreHome)));
        setScoreAway(String(leagueMatchNumber(result.scoreAway)));
      }
      if (source === "realtime") setMessage("Estado actualizado desde PostgreSQL");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar el estado canónico.");
    } finally {
      setLoading(false);
    }
  }, [endpoint, identity, surface]);

  useEffect(() => {
    if (previewData) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const sessionResult = await supabase?.auth.getSession();
      if (!active) return;
      const token = sessionResult?.data.session?.access_token ?? "";
      const actorId = sessionResult?.data.session?.user.id ?? "";
      if (!props.publicView && (!token || !actorId)) {
        setLoading(false);
        setMessage("Inicia sesión para consultar esta operación de Liga.");
        return;
      }
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(cacheKey(surface, identity, actorId));
      if (local) { setData(local); setCached(true); setLoading(false); }
      await loadCanonical(token, actorId, "initial");
      if (!supabase || !token) return;
      channel = supabase.channel(`league-match-operations:${surface}:${identity}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: leagueMatchOperationsRealtimeTable }, (payload) => {
          if (!invalidationMatches(props, data, payload)) return;
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(token, actorId, "realtime"), 120);
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") void loadCanonical(token, actorId, "realtime");
        });
      const reconcile = () => void loadCanonical(token, actorId, "realtime");
      window.addEventListener("online", reconcile);
      return () => window.removeEventListener("online", reconcile);
    };
    let removeOnline: (() => void) | undefined;
    void start().then((cleanup) => { removeOnline = cleanup; });
    return () => {
      active = false;
      removeOnline?.();
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  // The canonical data object is intentionally not a subscription dependency.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identity, loadCanonical, previewData, props.competitionId, props.divisionId, props.groupId, props.matchId, props.publicView, props.stageId, surface]);

  const command: Command = useCallback(async (action, expectedRevision, payload = {}, aggregateOverride = "") => {
    if (previewData) { setMessage("Laboratorio visual: no se ha enviado ninguna escritura."); return; }
    const context = leagueMatchRecord(data?.context);
    const aggregateId = aggregateOverride || leagueMatchText(context.id);
    if (!accessToken || !aggregateId) { setMessage("No hay sesión o agregado canónico para esta operación."); return; }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:league-match-operations-command", "/api/competitions/match-operations/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = leagueMatchRecord(await response.json());
      if (!response.ok) throw new Error(leagueMatchText(body.message) || "Operación no confirmada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL");
      await loadCanonical(accessToken, userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Recuperando el estado oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
    } finally { setBusy(false); }
  }, [accessToken, data, loadCanonical, previewData, userId]);

  const title = surface === "match" ? "Partido de Liga" : surface === "results" ? "Resultados" : surface === "standings" ? "Clasificación" : "Mis partidos de Liga";
  const shellContext = { detail: previewData ? "Laboratorio local" : cached ? "Copia local revalidándose" : "Snapshot canónico", eyebrow: "League Engine R4C", status: previewData ? "Solo visual" : loading ? "Sincronizando" : "Servidor", title };
  const tabs = [
    { id: "resumen", label: "Partido" },
    { id: "asistencia", label: "Asistencia" },
    { id: "convocatoria", label: "Alineación" },
    { id: "resultado", label: "Resultado" },
    ...(!previewData || props.disciplinePreviewData ? [{ id: "disciplina", label: "Disciplina" }] : []),
  ];

  const content = <main className={styles.page} data-match-operations-surface={surface} data-mobile-tab={surface === "standings" || surface === "my" ? "equipo" : "partido"}>
      <GamePageHeader eyebrow="Competición oficial" title={title} />
      {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /no |error|stale|rechaz|inicia/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
      {loading && !data ? <section className={styles.emptyState}><strong>Recuperando snapshot oficial</strong></section> : null}
      {!loading && !data ? <section className={styles.emptyState}><strong>R4C no está disponible para este contexto</strong></section> : null}
      {data && !previewData && !flagEnabled(data) ? <ProductFeedback tone="info">League Match Operations está instalada pero inactiva.</ProductFeedback> : null}
      {data && surface === "match" ? <>
        <MatchScoreboard data={data} />
        <div className={styles.matchWorkspace}>
          <nav className={styles.matchNav} aria-label="Secciones del partido">{tabs.map((tab) => <button aria-current={activeSection === tab.id ? "page" : undefined} key={tab.id} onClick={() => setActiveSection(tab.id)} type="button">{tab.label}</button>)}</nav>
          <div className={styles.matchContent}>
            {activeSection === "resumen" ? <MatchOverview data={data} /> : null}
            {activeSection === "asistencia" ? <AttendancePanel busy={busy} command={command} data={data} /> : null}
            {activeSection === "convocatoria" ? <SquadPanel busy={busy} command={command} data={data} memberRole={memberRole} rosterSelection={rosterSelection} setMemberRole={setMemberRole} setRosterSelection={setRosterSelection} /> : null}
            {activeSection === "resultado" ? <ResultPanel actingEntryId={actingEntryId} busy={busy} command={command} data={data} evidence={evidence} explanation={explanation} reason={reason} scoreAway={scoreAway} scoreHome={scoreHome} scorerGoals={scorerGoals} setActingEntryId={setActingEntryId} setEvidence={setEvidence} setExplanation={setExplanation} setReason={setReason} setScoreAway={setScoreAway} setScoreHome={setScoreHome} setScorerGoals={setScorerGoals} /> : null}
            {activeSection === "disciplina" ? <CompetitionDisciplineClient competitionId={competitionId} embedded matchId={props.matchId} previewData={props.disciplinePreviewData} surface="match" /> : null}
          </div>
        </div>
      </> : null}
      {data && surface === "results" ? <ResultDesk competitionId={competitionId} data={data} /> : null}
      {data && surface === "standings" ? <StandingsView data={data} /> : null}
      {data && surface === "my" ? <MyMatchOperations data={data} /> : null}
    </main>;
  return embedded
    ? content
    : <OfficialProductShellV2 active={surface === "standings" || surface === "my" ? "equipo" : "partido"} context={shellContext}>{content}</OfficialProductShellV2>;
}
