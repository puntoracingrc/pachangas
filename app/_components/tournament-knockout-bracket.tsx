"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  tournamentArray,
  tournamentBoolean,
  tournamentNumber,
  tournamentRecord,
  tournamentStatusTone,
  tournamentText,
  type TournamentJson,
} from "../tournament-draw-contract";
import {
  buildTournamentKnockoutReservationIntent,
  type TournamentKnockoutAction,
} from "../tournament-knockout-contract";
import {
  MetricTile,
  ResponsiveActionBar,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./tournament-knockout-bracket.module.css";

export type TournamentKnockoutCommandOptions = {
  action: TournamentKnockoutAction;
  payload?: TournamentJson;
};

type Props = {
  busy: boolean;
  command: (options: TournamentKnockoutCommandOptions) => Promise<boolean>;
  competitionId: string;
  data: TournamentJson;
};

function status(value: unknown) {
  return <StatusChip tone={tournamentStatusTone(value)}>{tournamentText(value, "pendiente").replaceAll("_", " ")}</StatusChip>;
}

function formatDateTime(value: unknown) {
  const date = new Date(tournamentText(value));
  if (!Number.isFinite(date.getTime())) return "Sin horario";
  return new Intl.DateTimeFormat("es-ES", {
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
  }).format(date);
}

function reservationStartSuggestion() {
  const initial = new Date();
  initial.setHours(initial.getHours() + 48, 0, 0, 0);
  return `${initial.getFullYear()}-${String(initial.getMonth() + 1).padStart(2, "0")}-${String(initial.getDate()).padStart(2, "0")}T${String(initial.getHours()).padStart(2, "0")}:00`;
}

function scoreLabel(match: TournamentJson) {
  const home = match.scoreHome;
  const away = match.scoreAway;
  if (home == null || away == null) return "–";
  const parts = [`${tournamentNumber(home)}-${tournamentNumber(away)}`];
  if (tournamentText(match.resolutionKind) === "EXTRA_TIME") parts.push("prórroga");
  if (tournamentText(match.resolutionKind) === "PENALTY_SHOOTOUT") {
    parts.push(`pen. ${tournamentNumber(match.shootoutHome)}-${tournamentNumber(match.shootoutAway)}`);
  }
  return parts.join(" · ");
}

export function TournamentKnockoutBracket({ busy, command, competitionId, data }: Props) {
  const rounds = tournamentArray(data.rounds).map(tournamentRecord);
  const bracket = tournamentRecord(data.bracket);
  const completion = tournamentRecord(data.completion);
  const organizer = tournamentRecord(data.organizerDesk);
  const permissions = tournamentRecord(data.permissions);
  const firstOpen = rounds.find((round) => tournamentArray(round.nodes).some((node) => !["advanced", "cancelled"].includes(tournamentText(tournamentRecord(node).status)))) ?? rounds.at(-1) ?? rounds[0];
  const [requestedRound, setRequestedRound] = useState(tournamentText(firstOpen?.code));
  const roundRailRef = useRef<HTMLElement>(null);
  const activeRoundRef = useRef<HTMLButtonElement>(null);
  const selected = rounds.find((round) => tournamentText(round.code) === requestedRound) ?? firstOpen;
  const selectedCode = tournamentText(selected?.code);
  const nodes = tournamentArray(selected?.nodes).map(tournamentRecord);
  const journeys = tournamentArray(data.teamJourneys).map(tournamentRecord);
  const entryById = new Map(journeys.map((journey) => {
    const entry = tournamentRecord(journey.entry);
    return [tournamentText(entry.entryId), entry] as const;
  }));
  const champion = entryById.get(tournamentText(completion.championEntryId)) ?? {};
  const runnerUp = entryById.get(tournamentText(completion.runnerUpEntryId)) ?? {};
  const allAdvanced = rounds.every((round) => tournamentArray(round.nodes).every((node) => tournamentText(tournamentRecord(node).status) === "advanced"));
  useEffect(() => {
    const rail = roundRailRef.current;
    const revealActiveRound = () => {
      const activeRound = activeRoundRef.current;
      if (!rail || !activeRound) return;
      const railRect = rail.getBoundingClientRect();
      const activeRect = activeRound.getBoundingClientRect();
      if (activeRect.left < railRect.left) rail.scrollLeft += activeRect.left - railRect.left;
      else if (activeRect.right > railRect.right) rail.scrollLeft += activeRect.right - railRect.right;
    };
    revealActiveRound();
    if (!rail || typeof ResizeObserver === "undefined") return;
    const resizeObserver = new ResizeObserver(revealActiveRound);
    resizeObserver.observe(rail);
    return () => resizeObserver.disconnect();
  }, [selectedCode]);

  return <div className={styles.root} data-tournament-knockout="r6c">
    {tournamentText(champion.name) ? <section className={styles.champion}>
      <div><span>Campeón</span><strong>{tournamentText(champion.name)}</strong><small>Subcampeón · {tournamentText(runnerUp.name, "Pendiente")}</small></div>
      {status(bracket.status)}
    </section> : null}
    <section className={styles.metrics}>
      <MetricTile label="Formato" value={`${tournamentNumber(bracket.size)} equipos`} />
      <MetricTile label="Rondas" value={rounds.length} />
      <MetricTile label="Sin resolver" value={tournamentNumber(organizer.unresolvedNodes)} />
      <MetricTile label="Sin horario" value={tournamentNumber(organizer.matchesWithoutSchedule)} />
      <MetricTile label="Revisión" value={tournamentNumber(bracket.revision)} />
    </section>
    <section className={styles.workspace}>
      <nav ref={roundRailRef} className={styles.roundRail} aria-label="Rondas eliminatorias">
        {rounds.map((round) => <button
          ref={tournamentText(round.code) === selectedCode ? activeRoundRef : undefined}
          aria-pressed={tournamentText(round.code) === selectedCode}
          key={tournamentText(round.code)}
          onClick={() => setRequestedRound(tournamentText(round.code))}
          type="button"
        ><strong>{tournamentText(round.label)}</strong><small>{tournamentArray(round.nodes).filter((node) => tournamentText(tournamentRecord(node).status) === "advanced").length}/{tournamentArray(round.nodes).length}</small></button>)}
      </nav>
      <div className={styles.roundBoard}>
        <SectionHeader eyebrow={tournamentText(selected?.status, "ACTIVE").replaceAll("_", " ")} title={tournamentText(selected?.label, "Eliminatoria")} />
        <div className={styles.nodeGrid}>{nodes.map((node) => <KnockoutNode
          busy={busy}
          command={command}
          competitionId={competitionId}
          key={tournamentText(node.id)}
          node={node}
          permissions={permissions}
        />)}</div>
      </div>
      <aside className={styles.organizerDesk}>
        <SectionHeader eyebrow="Organizer Desk" title={tournamentText(organizer.nextAction, "Seguimiento").replaceAll("_", " ")} />
        <dl>
          <Info label="Sin árbitro" value={tournamentNumber(organizer.matchesWithoutReferee)} />
          <Info label="Resultados pendientes" value={tournamentNumber(organizer.pendingResults)} />
          <Info label="Revisión requerida" value={tournamentNumber(organizer.reviewRequired)} />
          <Info label="Invalidaciones" value={tournamentNumber(organizer.invalidations)} />
        </dl>
        {tournamentBoolean(permissions.manageBracket) ? <ResponsiveActionBar>
          {nodes.length > 0 && nodes.every((node) => tournamentText(node.status) === "advanced") ? <button disabled={busy} onClick={() => void command({ action: "bracket.complete_round", payload: { reason: `Completar ${selectedCode}`, roundCode: selectedCode } })} type="button">Completar ronda</button> : null}
          {tournamentText(selected?.status) === "COMPLETED" ? <button disabled={busy} onClick={() => void command({ action: "bracket.lock_round", payload: { reason: `Bloquear ${selectedCode}`, roundCode: selectedCode } })} type="button">Bloquear ronda</button> : null}
          {allAdvanced && !tournamentText(completion.championEntryId) ? <button disabled={busy} onClick={() => void command({ action: "tournament.completion.rebuild", payload: { reason: "Reconstruir campeón desde el cuadro oficial" } })} type="button">Resolver campeón</button> : null}
          {allAdvanced && tournamentText(completion.championEntryId) && tournamentText(bracket.status) === "active" ? <button disabled={busy} onClick={() => void command({ action: "tournament.complete", payload: { reason: "Completar torneo con cuadro oficial" } })} type="button">Completar torneo</button> : null}
          {tournamentText(bracket.status) === "completed" ? <button disabled={busy} onClick={() => void command({ action: "tournament.lock", payload: { reason: "Bloquear torneo completado" } })} type="button">Bloquear torneo</button> : null}
        </ResponsiveActionBar> : null}
      </aside>
    </section>
  </div>;
}

function KnockoutNode({ busy, command, competitionId, node, permissions }: {
  busy: boolean;
  command: Props["command"];
  competitionId: string;
  node: TournamentJson;
  permissions: TournamentJson;
}) {
  const home = tournamentRecord(node.home);
  const away = tournamentRecord(node.away);
  const match = tournamentRecord(node.match);
  const reservation = tournamentRecord(node.reservation);
  const referee = tournamentRecord(node.referee);
  const winnerId = tournamentText(tournamentRecord(node.winner).entryId);
  const canManage = tournamentBoolean(permissions.manageBracket);
  const matchReady = ["ready", "scheduled"].includes(tournamentText(node.status));
  const [reservationStartsAt, setReservationStartsAt] = useState<string | null>(null);
  return <article className={styles.node} data-status={tournamentText(node.status)}>
    <header><span>Partido {tournamentNumber(node.nodeOrder)}</span>{status(node.status)}</header>
    <TeamLine entry={home} score={match.scoreHome} winnerId={winnerId} />
    <TeamLine entry={away} score={match.scoreAway} winnerId={winnerId} />
    <div className={styles.result}><strong>{scoreLabel(match)}</strong><small>{tournamentText(match.resolutionKind, "Resultado pendiente").replaceAll("_", " ")}</small></div>
    <footer><span>{formatDateTime(reservation.startsAt || match.scheduledStart)}</span><span>{tournamentText(reservation.venueLabel, tournamentText(match.venueLabel, "Sede pendiente"))}</span><span>{tournamentText(referee.displayName, "Sin árbitro")}</span></footer>
    {tournamentText(match.contextId) ? <Link href={`/competiciones/${competitionId}/partidos/${tournamentText(match.contextId)}`}>Abrir partido</Link> : null}
    {canManage && tournamentText(node.status) !== "advanced" ? <div className={styles.nodeActions}>
      {!tournamentText(reservation.id) ? <button disabled={busy} onClick={() => setReservationStartsAt((value) => value ? null : reservationStartSuggestion())} type="button">Programar</button> : null}
      {matchReady && tournamentText(reservation.id) && !tournamentText(match.contextId) ? <button disabled={busy} onClick={() => void command({ action: "bracket.node.generate_match", payload: { nodeId: tournamentText(node.id), reason: "Generar partido reservado desde Tournament Hub" } })} type="button">Crear partido</button> : null}
      {tournamentText(match.officialDecisionId) ? <button disabled={busy} onClick={() => void command({ action: "bracket.result.advance", payload: { officialDecisionId: tournamentText(match.officialDecisionId), reason: "Aplicar decisión oficial R4C" } })} type="button">Aplicar resultado</button> : null}
      {tournamentText(match.contextId) && !["played", "official", "advanced", "in_progress"].includes(tournamentText(node.status)) ? <button disabled={busy} onClick={() => void command({ action: "bracket.admin.replace_downstream", payload: { nodeId: tournamentText(node.id), reason: "Reemplazar partido no iniciado conservando lineage" } })} type="button">Reemplazar</button> : null}
    </div> : null}
    {reservationStartsAt ? <ReservationForm busy={busy} command={command} initialStartsAt={reservationStartsAt} nodeId={tournamentText(node.id)} onDone={() => setReservationStartsAt(null)} /> : null}
  </article>;
}

function ReservationForm({ busy, command, initialStartsAt, nodeId, onDone }: {
  busy: boolean;
  command: Props["command"];
  initialStartsAt: string;
  nodeId: string;
  onDone: () => void;
}) {
  const [startsAt, setStartsAt] = useState(initialStartsAt);
  const [venueLabel, setVenueLabel] = useState("");
  return <form className={styles.reservationForm} onSubmit={(event) => {
    event.preventDefault();
    const payload = buildTournamentKnockoutReservationIntent({
      durationMinutes: 90,
      nodeId,
      startsAt,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Madrid",
      venueLabel,
    });
    void command({ action: "bracket.reserve_slot", payload }).then((confirmed) => {
      if (confirmed) onDone();
    });
  }}>
    <label>Fecha<input required type="datetime-local" value={startsAt} onChange={(event) => setStartsAt(event.target.value)} /></label>
    <label>Sede<input maxLength={160} required value={venueLabel} onChange={(event) => setVenueLabel(event.target.value)} /></label>
    <button disabled={busy || !startsAt || !venueLabel.trim()} type="submit">Confirmar</button>
  </form>;
}

function TeamLine({ entry, score, winnerId }: { entry: TournamentJson; score: unknown; winnerId: string }) {
  const entryId = tournamentText(entry.entryId);
  return <div className={styles.team} data-winner={Boolean(entryId && entryId === winnerId)}>
    <span>{tournamentText(entry.name, "Por determinar")}</span>
    <b>{score == null ? "–" : tournamentNumber(score)}</b>
  </div>;
}

function Info({ label, value }: { label: string; value: ReactNode }) {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}
