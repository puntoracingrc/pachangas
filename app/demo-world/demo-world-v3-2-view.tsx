"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type {
  SyntheticSeasonCheckpoint,
  SyntheticSeasonCheckpointId,
  SyntheticSeasonIndex,
  SyntheticSeasonMatch,
  SyntheticSeasonSurface,
} from "./demo-world-v3-2-contract";
import { loadSyntheticSeasonCheckpoint } from "./demo-world-v2-client-state";
import styles from "./demo-world-v3-2-view.module.css";

const surfaces: Array<{ id: SyntheticSeasonSurface; label: string }> = [
  { id: "overview", label: "Resumen" },
  { id: "leagues", label: "Ligas" },
  { id: "tournaments", label: "Torneos" },
  { id: "rounds", label: "Jornadas" },
  { id: "matches", label: "Partidos" },
  { id: "standings", label: "Clasificaciones" },
  { id: "bracket", label: "Cuadros" },
  { id: "discipline", label: "Disciplina" },
  { id: "referees", label: "Árbitros" },
  { id: "teams", label: "Equipos" },
  { id: "clubs", label: "Clubs" },
  { id: "marketplace", label: "Mercado" },
  { id: "challenges", label: "Retos" },
  { id: "organizer", label: "Organización" },
  { id: "incidents", label: "Incidencias" },
  { id: "timeline", label: "Timeline" },
];

function matchDate(value: string) {
  return new Intl.DateTimeFormat("es-ES", {
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
    timeZone: "Europe/Madrid",
  }).format(new Date(value));
}

function Stat({ label, value }: { label: string; value: number | string }) {
  return <span className={styles.stat}><strong>{value}</strong><small>{label}</small></span>;
}

function Status({ value }: { value: string }) {
  return <span className={styles.status} data-status={value.toLowerCase()}>{value.replaceAll("_", " ")}</span>;
}

function MatchRow({ match, teamName }: { match: SyntheticSeasonMatch; teamName: (id: string) => string }) {
  return (
    <article className={styles.matchRow}>
      <div>
        <small>{match.stage.replaceAll("_", " ")} · {matchDate(match.scheduledAt)}</small>
        <strong>{teamName(match.homeTeamId)} <b>{match.result.home}-{match.result.away}</b> {teamName(match.awayTeamId)}</strong>
      </div>
      <span><Status value={match.anomaly} />{match.refereeId ? <small>Árbitro</small> : <small>Sin árbitro</small>}</span>
    </article>
  );
}

function Table({ children, headers }: { children: ReactNode; headers: string[] }) {
  return <div className={styles.tableWrap}><table><thead><tr>{headers.map((header) => <th key={header}>{header}</th>)}</tr></thead><tbody>{children}</tbody></table></div>;
}

function SeasonSurface({ checkpoint, index, selectedCompetitionId, selectedTeamId, setSelectedCompetitionId, setSelectedTeamId, surface }: {
  checkpoint: SyntheticSeasonCheckpoint;
  index: SyntheticSeasonIndex;
  selectedCompetitionId: string;
  selectedTeamId: string;
  setSelectedCompetitionId: (value: string) => void;
  setSelectedTeamId: (value: string) => void;
  surface: SyntheticSeasonSurface;
}) {
  const teamName = (id: string) => index.teams.find((team) => team.id === id)?.name ?? id;
  const clubName = (id: string) => index.clubs.find((club) => club.id === id)?.name ?? id;
  const selectedCompetition = index.competitions.find(({ id }) => id === selectedCompetitionId) ?? index.competitions[0]!;
  const selectedTeam = checkpoint.operationalStates.find(({ id }) => id === selectedTeamId) ?? checkpoint.operationalStates[0]!;
  const competitionMatches = [...checkpoint.matches.official, ...checkpoint.matches.upcoming]
    .filter(({ competitionId }) => competitionId === selectedCompetition.id);

  if (surface === "overview") return <>
    <section className={styles.metrics}>
      <Stat label="Clubs" value={index.proof.counts.clubs} />
      <Stat label="Equipos" value={index.proof.counts.teams} />
      <Stat label="Jugadores" value={index.proof.counts.players} />
      <Stat label="Partidos" value={index.proof.counts.matches} />
      <Stat label="Oficiales" value={checkpoint.matches.official.length} />
      <Stat label="Semana" value={checkpoint.week} />
    </section>
    <section className={styles.summaryBand}>
      <div><span>Autoridad central</span><strong>PostgreSQL + motores productivos</strong><p>Los snapshots son proyecciones inmutables. Cambiar de semana nunca ejecuta una operación.</p></div>
      <div><span>Salud de invariantes</span><strong>{Object.values(index.proof.invariants).every(Boolean) ? "Todo consistente" : "Revisión necesaria"}</strong><p>{Object.keys(index.proof.invariants).length} invariantes deportivas, temporales y de privacidad verificadas.</p></div>
    </section>
    <section className={styles.section}><header><span>Esta etapa</span><h3>{checkpoint.label}</h3></header>{checkpoint.changes.summary.map((item) => <p className={styles.timelineItem} key={item}>{item}</p>)}</section>
  </>;

  if (surface === "leagues" || surface === "tournaments") {
    const kind = surface === "leagues" ? "LEAGUE" : "TOURNAMENT";
    return <section className={styles.cardGrid}>{index.competitions.filter((competition) => competition.kind === kind).map((competition) => <button className={styles.competitionCard} data-selected={competition.id === selectedCompetitionId} key={competition.id} onClick={() => { setSelectedCompetitionId(competition.id); }} type="button"><span>{competition.modality === "FOOTBALL_7" ? "Fútbol 7" : "Fútbol sala"}</span><strong>{competition.name}</strong><small>{competition.visibility} · {competition.teamIds.length} equipos</small><Status value={competition.status} /></button>)}</section>;
  }

  if (surface === "rounds") {
    const rounds = competitionMatches.reduce((grouped, match) => {
      grouped.set(match.round, [...(grouped.get(match.round) ?? []), match]);
      return grouped;
    }, new Map<number, SyntheticSeasonMatch[]>());
    return <section className={styles.rounds}>{[...rounds].sort(([a], [b]) => a - b).map(([round, matches]) => <article key={round}><header>Jornada {round}</header>{matches.slice(0, 6).map((match) => <MatchRow key={match.canonicalMatchId} match={match} teamName={teamName} />)}</article>)}</section>;
  }

  if (surface === "matches") return <section className={styles.matchList}>{checkpoint.matches.official.slice().reverse().map((match) => <MatchRow key={match.canonicalMatchId} match={match} teamName={teamName} />)}{checkpoint.matches.official.length === 0 ? <p className={styles.empty}>Aún no hay resultados oficiales en este checkpoint.</p> : null}</section>;

  if (surface === "standings") {
    const rows = checkpoint.standings[selectedCompetition.id] ?? [];
    return <section className={styles.section}><header><span>Clasificación canónica</span><h3>{selectedCompetition.name}</h3></header><Table headers={["POS", "EQUIPO", "PJ", "G", "E", "P", "GF", "GC", "DG", "PTS"]}>{rows.map((row) => <tr key={row.teamId}><td>{row.position}</td><td>{teamName(row.teamId)}</td><td>{row.played}</td><td>{row.wins}</td><td>{row.draws}</td><td>{row.losses}</td><td>{row.goalsFor}</td><td>{row.goalsAgainst}</td><td>{row.goalDifference}</td><td><strong>{row.points}</strong></td></tr>)}</Table></section>;
  }

  if (surface === "bracket") return <section className={styles.bracket}>{checkpoint.bracket.map((node) => <article key={node.id}><header>{node.round.replaceAll("_", " ")}</header><span>{teamName(node.homeTeamId)}</span><span>{teamName(node.awayTeamId)}</span><strong>Avanza: {teamName(node.winnerTeamId)}</strong></article>)}{checkpoint.bracket.length === 0 ? <p className={styles.empty}>El cuadro se publica después de la clasificación canónica.</p> : null}</section>;

  if (surface === "discipline") return <><section className={styles.metrics}><Stat label="Eventos" value={checkpoint.discipline.eventCount} /><Stat label="Sanciones" value={checkpoint.discipline.sanctionCount} /><Stat label="No elegibles" value={checkpoint.discipline.ineligiblePlayers} /><Stat label="Cumplidas" value={checkpoint.discipline.fulfilledSanctions} /></section><section className={styles.summaryBand}><div><span>Linaje</span><strong>Árbitro + Assignment + partido</strong><p>Los eventos arbitrados conservan la referencia canónica sin permitir al árbitro decidir la sanción.</p></div><div><span>Elegibilidad</span><strong>Reconstruible por cronología</strong><p>Tarjeta, sanción, partido no elegible, cumplimiento y regreso disponible.</p></div></section></>;

  if (surface === "referees") return <section className={styles.cardGrid}>{index.referees.map((referee) => { const stats = checkpoint.refereeStats.find(({ refereeId }) => refereeId === referee.id); return <article className={styles.entityCard} key={referee.id}><span>{referee.zone}</span><strong>{referee.name}</strong><small>{referee.modalities.map((value) => value === "FOOTBALL_7" ? "F7" : "Sala").join(" · ")}</small><p>{stats?.completed ?? 0} completados · {stats?.replacements ?? 0} sustituciones</p></article>; })}</section>;

  if (surface === "teams") return <><label className={styles.selector}>Equipo<select value={selectedTeam.id} onChange={(event) => setSelectedTeamId(event.target.value)}>{checkpoint.operationalStates.map((team) => <option key={team.id} value={team.id}>{team.name}</option>)}</select></label><section className={styles.summaryBand}><div><span>Estado operativo</span><strong>{selectedTeam.name}</strong><p><Status value={selectedTeam.state} /> · {selectedTeam.restrictionPreset.replaceAll("_", " ")}</p></div><div><span>Continuidad deportiva</span><strong>{selectedTeam.competitionContinuity ? "Preservada" : "Bloqueada"}</strong><p>Mercado {selectedTeam.marketplaceAllowed ? "activo" : "bloqueado"} · Retos {selectedTeam.challengesAllowed ? "activos" : "bloqueados"}</p></div></section><section className={styles.cardGrid}>{checkpoint.operationalStates.map((team) => <button className={styles.entityCard} data-selected={team.id === selectedTeam.id} key={team.id} onClick={() => setSelectedTeamId(team.id)} type="button"><span>{team.publicLocation}</span><strong>{team.name}</strong><Status value={team.state} /></button>)}</section></>;

  if (surface === "clubs") return <section className={styles.cardGrid}>{index.clubs.map((club) => <article className={styles.entityCard} key={club.id}><span>{club.organizerAccess.replaceAll("_", " ")}</span><strong>{club.name}</strong><small>{club.teamIds.length} equipos</small><p>{club.story}</p><Status value={club.status} /></article>)}</section>;

  if (surface === "marketplace") return <section className={styles.cardGrid}>{checkpoint.operationalStates.filter(({ marketplaceAllowed }) => marketplaceAllowed).map((team) => <article className={styles.entityCard} key={team.id}><span>{team.publicLocation}</span><strong>{team.name}</strong><small>Disponible para completar partidos</small></article>)}</section>;

  if (surface === "challenges") return <section className={styles.matchList}>{checkpoint.matches.official.filter(({ kind }) => kind === "CHALLENGE").map((match) => <MatchRow key={match.canonicalMatchId} match={match} teamName={teamName} />)}{checkpoint.matches.official.every(({ kind }) => kind !== "CHALLENGE") ? <p className={styles.empty}>Los retos empezarán cuando se abra la temporada.</p> : null}</section>;

  if (surface === "organizer") return <><section className={styles.metrics}><Stat label="Solicitudes" value={index.proof.counts.organizerApplications} /><Stat label="Grants" value={index.proof.counts.organizerGrants} /><Stat label="Stripe calls" value={0} /><Stat label="Cargos" value={0} /></section><section className={styles.cardGrid}>{index.clubs.map((club) => <article className={styles.entityCard} key={club.id}><span>{club.organizerAccess.replaceAll("_", " ")}</span><strong>{club.name}</strong><small>{clubName(club.id)}</small><p>{club.publicInDemo ? "Perfil público solo en Demo" : "Privado o no listado"}</p></article>)}</section></>;

  if (surface === "incidents") return <section className={styles.incidentList}>{index.proof.faultInjection.map((fault) => <article key={fault.code}><span>{fault.loserOutcome}</span><strong>{fault.name.replaceAll("_", " ")}</strong><small>Ganador canónico: {fault.canonicalWinner}</small></article>)}</section>;

  return <section className={styles.timeline}>{index.checkpointFiles.map((item) => <article data-current={item.checkpoint === checkpoint.checkpoint} key={item.checkpoint}><span>Checkpoint {item.checkpoint}</span><strong>{item.label}</strong><small>Semana {item.week} · {item.hash.slice(0, 10)}</small></article>)}</section>;
}

export function SyntheticSeasonView({ index }: { index: SyntheticSeasonIndex }) {
  const cache = useRef(new Map<SyntheticSeasonCheckpointId, SyntheticSeasonCheckpoint>());
  const [checkpointId, setCheckpointId] = useState<SyntheticSeasonCheckpointId>(4);
  const [checkpoint, setCheckpoint] = useState<SyntheticSeasonCheckpoint | null>(null);
  const [surface, setSurface] = useState<SyntheticSeasonSurface>("overview");
  const [selectedCompetitionId, setSelectedCompetitionId] = useState(index.competitions[0]!.id);
  const [selectedTeamId, setSelectedTeamId] = useState(index.teams[0]!.id);
  const [playing, setPlaying] = useState(false);
  const [error, setError] = useState("");
  const reducedMotion = useMemo(() => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches, []);

  useEffect(() => {
    let cancelled = false;
    const descriptor = index.checkpointFiles.find((item) => item.checkpoint === checkpointId)!;
    const cached = cache.current.get(checkpointId);
    if (cached) {
      setCheckpoint(cached);
      setError("");
      return () => { cancelled = true; };
    }
    setError("");
    void loadSyntheticSeasonCheckpoint(descriptor.path).then((value) => {
      if (cancelled) return;
      cache.current.set(checkpointId, value);
      setCheckpoint(value);
    }).catch(() => {
      if (!cancelled) setError("No se pudo abrir este checkpoint inmutable.");
    });
    return () => { cancelled = true; };
  }, [checkpointId, index.checkpointFiles]);

  useEffect(() => {
    void Promise.all(index.checkpointFiles.map(async (descriptor) => {
      if (cache.current.has(descriptor.checkpoint)) return;
      const value = await loadSyntheticSeasonCheckpoint(descriptor.path);
      cache.current.set(descriptor.checkpoint, value);
    })).catch(() => undefined);
  }, [index.checkpointFiles]);

  useEffect(() => {
    if (!playing || reducedMotion) return;
    const timer = window.setTimeout(() => {
      setCheckpointId((current) => current === 8 ? 0 : (current + 1) as SyntheticSeasonCheckpointId);
    }, 2200);
    return () => window.clearTimeout(timer);
  }, [checkpointId, playing, reducedMotion]);

  const descriptor = index.checkpointFiles.find((item) => item.checkpoint === checkpointId)!;
  return (
    <section className={styles.season} data-season-checkpoint={checkpointId} data-season-surface={surface}>
      <header className={styles.hero}>
        <div><span>Demo World V3.2 · Synthetic Live Season</span><h2>Temporada 2026/27</h2><p>Dieciséis semanas reproducibles con los motores reales y cero entidades reales.</p></div>
        <button disabled={reducedMotion} title={reducedMotion ? "La reproducción automática respeta la reducción de movimiento" : undefined} type="button" onClick={() => setPlaying((value) => !value)}>{playing ? "Pausar" : "Reproducir temporada"}</button>
      </header>
      <div className={styles.surfaceTabs} role="navigation" aria-label="Vistas de temporada">{surfaces.map((item) => <button aria-current={surface === item.id ? "page" : undefined} key={item.id} type="button" onClick={() => setSurface(item.id)}>{item.label}</button>)}</div>
      <div className={styles.gameLayout}>
        <aside className={styles.weekRail} aria-label="Checkpoints de temporada">{index.checkpointFiles.map((item) => <button aria-current={checkpointId === item.checkpoint ? "step" : undefined} key={item.checkpoint} type="button" onClick={() => { setCheckpointId(item.checkpoint); setPlaying(false); }}><span>{item.checkpoint}</span><strong>{item.label}</strong><small>S{item.week}</small></button>)}</aside>
        <div className={styles.mainSurface}>
          <div className={styles.contextBar}><label>Competición<select value={selectedCompetitionId} onChange={(event) => setSelectedCompetitionId(event.target.value)}>{index.competitions.map((competition) => <option key={competition.id} value={competition.id}>{competition.name}</option>)}</select></label><span>{descriptor.label} · semana {descriptor.week}</span></div>
          {error ? <p className={styles.error}>{error}</p> : null}
          {!checkpoint ? <div className={styles.loading} role="status">Cargando checkpoint verificado…</div> : <SeasonSurface checkpoint={checkpoint} index={index} selectedCompetitionId={selectedCompetitionId} selectedTeamId={selectedTeamId} setSelectedCompetitionId={setSelectedCompetitionId} setSelectedTeamId={setSelectedTeamId} surface={surface} />}
        </div>
        <aside className={styles.changePanel}>
          <span>Qué cambió</span><h3>{checkpoint?.label ?? descriptor.label}</h3>
          {checkpoint?.changes.summary.map((item) => <p key={item}>{item}</p>)}
          <dl><div><dt>Resultados</dt><dd>{checkpoint?.changes.newOfficialResults ?? 0}</dd></div><div><dt>Tarjetas</dt><dd>{checkpoint?.changes.newDisciplineEvents ?? 0}</dd></div><div><dt>Árbitros</dt><dd>{checkpoint?.changes.refereeChanges ?? 0}</dd></div></dl>
          {checkpoint?.changes.champion ? <div className={styles.champion}><small>Campeón</small><strong>{index.teams.find(({ id }) => id === checkpoint.changes.champion)?.name}</strong></div> : null}
        </aside>
      </div>
    </section>
  );
}
