"use client";

import Image from "next/image";
import Link from "next/link";
import { useMemo, useState, type ReactNode } from "react";
import styles from "./official-match-experience.module.css";

export type OfficialAttendanceStatus = "duda" | "no" | "voy";

export type OfficialMatchSummary = {
  confirmed: number;
  date: string;
  draft?: boolean;
  id: string;
  kind: string;
  myStatus?: OfficialAttendanceStatus | null;
  openSlots: number;
  place: string;
  result?: { away: number; home: number } | null;
  targetPlayers: number;
  title: string;
};

export type OfficialMatchRosterPlayer = {
  avatar?: string;
  id: string;
  name: string;
  position: string;
  status: OfficialAttendanceStatus | null;
};

export type OfficialQuickMatchDraft = {
  date: string;
  fieldCost: string;
  groupInvited: boolean;
  guestsPay: boolean;
  kind: string;
  manualApproval: boolean;
  publicOpen: boolean;
  publicOpenSlots: string;
  reserveLimit: string;
  reservesAttend: boolean;
  targetPlayers: string;
  time: string;
  title: string;
  venueId: string;
};

type OfficialVenueOption = {
  id: string;
  label: string;
};

const dateFormatter = new Intl.DateTimeFormat("es-ES", {
  day: "2-digit",
  month: "short",
  weekday: "short",
});
const timeFormatter = new Intl.DateTimeFormat("es-ES", {
  hour: "2-digit",
  minute: "2-digit",
});

function parsedDate(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function matchDate(value: string) {
  const parsed = parsedDate(value);
  return parsed ? dateFormatter.format(parsed) : "Fecha pendiente";
}

function matchTime(value: string) {
  const parsed = parsedDate(value);
  return parsed ? timeFormatter.format(parsed) : "Hora pendiente";
}

function statusLabel(status: OfficialAttendanceStatus | null | undefined) {
  if (status === "voy") return "Voy";
  if (status === "duda") return "Duda";
  if (status === "no") return "No voy";
  return "Sin responder";
}

function MatchCard({
  history,
  match,
  onOpen,
  onRepeat,
}: {
  history?: boolean;
  match: OfficialMatchSummary;
  onOpen: () => void;
  onRepeat?: () => void;
}) {
  return (
    <article className={styles.matchCard} data-match-state={history ? "history" : "upcoming"}>
      <button className={styles.matchOpen} type="button" onClick={onOpen}>
        <span className={styles.matchDate}>{matchDate(match.date)} · {matchTime(match.date)}</span>
        <strong>{match.title}</strong>
        <small>{match.kind} · {match.place || "Campo por confirmar"}</small>
        {history && match.result ? (
          <b className={styles.score}>{match.result.home} - {match.result.away}</b>
        ) : (
          <span className={styles.matchNumbers}>
            <b>{match.confirmed}/{match.targetPlayers}</b>
            <small>{match.openSlots} plaza{match.openSlots === 1 ? "" : "s"}</small>
            {match.myStatus ? <em data-status={match.myStatus}>{statusLabel(match.myStatus)}</em> : null}
          </span>
        )}
      </button>
      {history && onRepeat ? (
        <button className={styles.repeatButton} type="button" onClick={onRepeat}>
          Repetir configuración
        </button>
      ) : null}
    </article>
  );
}

export function OfficialMatchesOverview({
  canManage,
  drafts,
  history,
  marketHref = "/mercado?tab=partidos",
  onCreate,
  onDiscardDraft,
  onOpen,
  onRepeat,
  onResumeDraft,
  upcoming,
}: {
  canManage: boolean;
  drafts: OfficialMatchSummary[];
  history: OfficialMatchSummary[];
  marketHref?: string;
  onCreate: () => void;
  onDiscardDraft: (matchId: string) => void;
  onOpen: (matchId: string, history: boolean) => void;
  onRepeat: (matchId: string) => void;
  onResumeDraft: (matchId: string) => void;
  upcoming: OfficialMatchSummary[];
}) {
  const [tab, setTab] = useState<"history" | "upcoming">("upcoming");
  const visibleMatches = tab === "upcoming" ? upcoming : history;

  return (
    <section className={styles.overview} data-official-match-experience="v3b" data-view="overview">
      <header className={styles.overviewHeader}>
        <div>
          <span>Partidos</span>
          <h1>Tu calendario de juego</h1>
        </div>
        {canManage ? <button className={styles.primaryButton} type="button" onClick={onCreate}>Crear partido</button> : null}
      </header>

      {canManage && drafts.length > 0 ? (
        <section className={styles.draftBand} aria-label="Borradores de partido">
          <header><span>Borrador pendiente</span><small>Solo visible para admins</small></header>
          {drafts.map((match) => (
            <article key={match.id}>
              <div><strong>{match.title}</strong><small>{matchDate(match.date)} · {match.place}</small></div>
              <div>
                <button type="button" onClick={() => onResumeDraft(match.id)}>Continuar</button>
                <button type="button" onClick={() => onDiscardDraft(match.id)}>Descartar</button>
              </div>
            </article>
          ))}
        </section>
      ) : null}

      <div className={styles.tabs} role="tablist" aria-label="Calendario de partidos">
        <button aria-selected={tab === "upcoming"} role="tab" type="button" onClick={() => setTab("upcoming")}>Próximos <b>{upcoming.length}</b></button>
        <button aria-selected={tab === "history"} role="tab" type="button" onClick={() => setTab("history")}>Historial <b>{history.length}</b></button>
      </div>

      {visibleMatches.length > 0 ? (
        <div className={styles.matchGrid} role="tabpanel">
          {visibleMatches.map((match) => (
            <MatchCard
              history={tab === "history"}
              key={match.id}
              match={match}
              onOpen={() => onOpen(match.id, tab === "history")}
              onRepeat={canManage && tab === "history" ? () => onRepeat(match.id) : undefined}
            />
          ))}
        </div>
      ) : (
        <div className={styles.emptyState} role="tabpanel">
          <div>
            <strong>{tab === "history" ? "Todavía no hay resultados" : "No hay partidos programados"}</strong>
            <p>{tab === "history" ? "Los partidos finalizados aparecerán aquí." : canManage ? "Crea el siguiente encuentro en tres pasos." : "Busca un partido abierto en Mercado."}</p>
          </div>
          {tab === "upcoming" ? canManage ? (
            <button className={styles.primaryButton} type="button" onClick={onCreate}>Crear partido</button>
          ) : (
            <Link className={styles.primaryButton} href={marketHref}>Buscar partido</Link>
          ) : null}
        </div>
      )}
    </section>
  );
}

export function OfficialQuickMatchWizard({
  draft,
  error,
  isSaving,
  kinds,
  onAddVenue,
  onCancel,
  onChange,
  onConfirm,
  onDiscard,
  venues,
}: {
  draft: OfficialQuickMatchDraft;
  error?: string;
  isSaving: boolean;
  kinds: Array<{ id: string; label: string; targetPlayers: number }>;
  onAddVenue?: () => void;
  onCancel: () => void;
  onChange: (patch: Partial<OfficialQuickMatchDraft>) => void;
  onConfirm: () => void;
  onDiscard: () => void;
  venues: OfficialVenueOption[];
}) {
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const selectedVenue = venues.find((venue) => venue.id === draft.venueId)?.label ?? "Campo por confirmar";
  const selectedKind = kinds.find((kind) => kind.id === draft.kind)?.label ?? "Modalidad pendiente";
  const stepOneReady = Boolean(draft.date && draft.time && draft.kind && draft.venueId);
  const stepTwoReady = Number(draft.targetPlayers) > 1 && (!draft.publicOpen || Number(draft.publicOpenSlots) > 0);

  return (
    <section className={styles.wizard} data-official-match-experience="v3b" data-view="wizard">
      <header className={styles.wizardHeader}>
        <div>
          <span>Nuevo partido</span>
          <h1>{step === 1 ? "Cuándo y dónde" : step === 2 ? "Jugadores y plazas" : "Revisar y crear"}</h1>
        </div>
        <button type="button" onClick={onCancel}>Cerrar</button>
      </header>

      <ol className={styles.steps} aria-label="Progreso de creación">
        {[1, 2, 3].map((entry) => <li aria-current={step === entry ? "step" : undefined} data-complete={entry < step} key={entry}><b>{entry}</b><span>{entry === 1 ? "Partido" : entry === 2 ? "Plazas" : "Confirmar"}</span></li>)}
      </ol>

      <div className={styles.wizardBody}>
        {step === 1 ? (
          <div className={styles.formGrid}>
            <label>Fecha<input type="date" value={draft.date} onChange={(event) => onChange({ date: event.target.value })} /></label>
            <label>Hora<input type="time" step="600" value={draft.time} onChange={(event) => onChange({ time: event.target.value })} /></label>
            <label>Modalidad<select value={draft.kind} onChange={(event) => {
              const nextKind = kinds.find((kind) => kind.id === event.target.value);
              onChange({ kind: event.target.value, targetPlayers: String(nextKind?.targetPlayers ?? draft.targetPlayers) });
            }}>{kinds.map((kind) => <option key={kind.id} value={kind.id}>{kind.label}</option>)}</select></label>
            <label className={styles.wideField}>Campo<select value={draft.venueId} onChange={(event) => onChange({ venueId: event.target.value })}><option value="" disabled>Selecciona campo</option>{venues.map((venue) => <option key={venue.id} value={venue.id}>{venue.label}</option>)}</select></label>
            {onAddVenue ? <button className={styles.inlineButton} type="button" onClick={onAddVenue}>Añadir campo</button> : null}
          </div>
        ) : null}

        {step === 2 ? (
          <div className={styles.formGrid}>
            <label>Jugadores objetivo<input min="2" inputMode="numeric" type="number" value={draft.targetPlayers} onChange={(event) => onChange({ targetPlayers: event.target.value })} /></label>
            <label className={styles.toggleField}><input checked={draft.groupInvited} type="checkbox" onChange={(event) => onChange({ groupInvited: event.target.checked })} /><span><b>Avisar al grupo</b><small>Todos podrán responder su asistencia.</small></span></label>
            <label className={styles.toggleField}><input checked={draft.publicOpen} type="checkbox" onChange={(event) => onChange({ publicOpen: event.target.checked })} /><span><b>Abrir plazas públicas</b><small>Publicar el partido en Mercado.</small></span></label>
            {draft.publicOpen ? <>
              <label>Plazas públicas<input min="1" inputMode="numeric" type="number" value={draft.publicOpenSlots} onChange={(event) => onChange({ publicOpenSlots: event.target.value })} /></label>
              <label className={styles.toggleField}><input checked={draft.manualApproval} type="checkbox" onChange={(event) => onChange({ manualApproval: event.target.checked })} /><span><b>Aprobación manual</b><small>Un admin decide quién entra.</small></span></label>
            </> : null}
          </div>
        ) : null}

        {step === 3 ? (
          <div className={styles.review}>
            <div><span>Fecha</span><strong>{draft.date} · {draft.time}</strong></div>
            <div><span>Partido</span><strong>{selectedKind} · {draft.targetPlayers} jugadores</strong></div>
            <div><span>Campo</span><strong>{selectedVenue}</strong></div>
            <div><span>Convocatoria</span><strong>{draft.groupInvited ? "Grupo avisado" : "Sin aviso inicial"}{draft.publicOpen ? ` · ${draft.publicOpenSlots} plazas públicas` : " · Privado"}</strong></div>
            <details className={styles.advanced}>
              <summary>Opciones avanzadas</summary>
              <div className={styles.formGrid}>
                <label>Coste del campo (€)<input min="0" inputMode="decimal" type="number" value={draft.fieldCost} onChange={(event) => onChange({ fieldCost: event.target.value })} /></label>
                <label className={styles.toggleField}><input checked={draft.reservesAttend} type="checkbox" onChange={(event) => onChange({ reservesAttend: event.target.checked })} /><span><b>Reservas presenciales</b><small>Las reservas van y pagan.</small></span></label>
                {draft.reservesAttend ? <label>Máximo reservas<input min="0" inputMode="numeric" type="number" value={draft.reserveLimit} onChange={(event) => onChange({ reserveLimit: event.target.value })} /></label> : null}
                {draft.publicOpen ? <label className={styles.toggleField}><input checked={draft.guestsPay} type="checkbox" onChange={(event) => onChange({ guestsPay: event.target.checked })} /><span><b>Invitados pagan</b><small>Se incluyen en el reparto del campo.</small></span></label> : null}
              </div>
            </details>
          </div>
        ) : null}
      </div>

      <footer className={styles.wizardFooter}>
        <button className={styles.dangerButton} type="button" onClick={onDiscard}>Descartar borrador</button>
        <span aria-live="polite">{error}</span>
        <div>
          {step > 1 ? <button type="button" onClick={() => setStep((step - 1) as 1 | 2)}>Atrás</button> : null}
          {step < 3 ? <button className={styles.primaryButton} disabled={step === 1 ? !stepOneReady : !stepTwoReady} type="button" onClick={() => setStep((step + 1) as 2 | 3)}>Continuar</button> : <button className={styles.primaryButton} disabled={isSaving || !stepOneReady || !stepTwoReady} type="button" onClick={onConfirm}>{isSaving ? "Confirmando..." : "Crear partido"}</button>}
        </div>
      </footer>
    </section>
  );
}

export function OfficialAttendancePanel({
  canRespond,
  currentStatus,
  isUpdating,
  message,
  onManagePlayer,
  onStatus,
  players,
  summary,
}: {
  canRespond: boolean;
  currentStatus: OfficialAttendanceStatus | null;
  isUpdating: boolean;
  message?: ReactNode;
  onManagePlayer?: (playerId: string) => void;
  onStatus: (status: OfficialAttendanceStatus) => void;
  players: OfficialMatchRosterPlayer[];
  summary: { confirmed: number; target: number };
}) {
  const groups = useMemo(() => [
    { id: "voy", label: "Confirmados", players: players.filter((player) => player.status === "voy") },
    { id: "duda", label: "Duda", players: players.filter((player) => player.status === "duda") },
    { id: "pending", label: "Sin respuesta", players: players.filter((player) => player.status === null) },
    { id: "no", label: "No van", players: players.filter((player) => player.status === "no") },
  ], [players]);

  return (
    <section className={styles.attendancePanel} data-official-match-attendance="v3b">
      <header className={styles.attendanceHeader}>
        <div><span>Asistencia</span><strong>{summary.confirmed}/{summary.target} confirmados</strong></div>
        {canRespond ? (
          <div className={styles.attendanceButtons} role="group" aria-label="Mi asistencia">
            {(["voy", "duda", "no"] as const).map((status) => (
              <button aria-pressed={currentStatus === status} disabled={isUpdating} key={status} type="button" onClick={() => onStatus(status)}>{statusLabel(status)}</button>
            ))}
          </div>
        ) : null}
      </header>
      <div className={styles.liveMessage} aria-live="polite">{message}</div>
      <div className={styles.rosterGroups}>
        {groups.map((group) => (
          <section data-roster-group={group.id} key={group.id}>
            <header><strong>{group.label}</strong><b>{group.players.length}</b></header>
            {group.players.length ? group.players.map((player) => (
              <article key={player.id}>
                {player.avatar ? <Image unoptimized src={player.avatar} alt="" width={40} height={40} /> : <span className={styles.avatarFallback} aria-hidden="true">{player.name.slice(0, 2).toUpperCase()}</span>}
                <div><strong>{player.name}</strong><small>{player.position}</small></div>
                {onManagePlayer ? <button type="button" aria-label={`Gestionar ${player.name}`} onClick={() => onManagePlayer(player.id)}>...</button> : <span className={styles.statusDot} data-status={player.status ?? "pending"} aria-label={statusLabel(player.status)} />}
              </article>
            )) : <p>Sin jugadores</p>}
          </section>
        ))}
      </div>
    </section>
  );
}
