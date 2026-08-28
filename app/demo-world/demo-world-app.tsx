"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { CompetitionDisciplineClient } from "../_components/competition-discipline-client";
import { CompetitionDirectoryClient } from "../competiciones/competition-directory-client";
import { PublicCompetitionHub } from "../competiciones/[competition]/public-competition-hub";
import { LeagueMatchOperationsClient } from "../_components/league-match-operations-client";
import { LeagueSchedulingClient } from "../_components/league-scheduling-client";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import { RefereeAssignmentsClient } from "../_components/referee-assignments-client";
import { RefereeProfileCard } from "../_components/referee-profile-card";
import { TeamShieldView } from "../_components/team-shield-view";
import { PublicClubProfile } from "../clubes/[slug]/public-club-profile";
import { MobileAppNav, type MobileAppTab } from "../mobile-app-nav";
import {
  organizerBillingDate,
  organizerBillingStatus,
  organizerFeatureLabels,
} from "../organizer-billing-contract";
import { PLAYER_COSMETIC_CATALOG, catalogEntry } from "../player-cosmetics-catalog";
import { withCosmeticKey } from "../player-cosmetics-contract";
import { ProvincialRankingBoard } from "../ranking/provincial-ranking-board";
import type { RefereeJson } from "../referee-platform-contract";
import { TEAM_SHIELD_RENDER_CATALOG } from "../team-shield-cosmetics-catalog";
import {
  type DemoMatchKind,
  type DemoWorldAchievement,
  type DemoWorldChallenge,
  type DemoWorldCoreChunk,
  type DemoWorldMatch,
  type DemoWorldMatchPane,
  type DemoWorldNotification,
  type DemoWorldPerspective,
  type DemoWorldPlayer,
  type DemoWorldRankingShowcaseId,
  type DemoWorldRewardBox,
  type DemoWorldSessionState,
  type DemoWorldTeam,
  canDemoWorldInvite,
  demoWorldMatchAdminActions,
  demoWorldMatchPaneForRole,
} from "./demo-world-contract";
import {
  demoAvatarDataUri,
  readInitialDemoWorldSession,
  resetDemoWorldSession,
  writeDemoWorldSession,
} from "./demo-world-client-state";
import {
  type DemoWorldV2Club,
  type DemoWorldV2ConfigurationChunk,
  type DemoWorldV2Manifest,
  type DemoWorldV2OrganizerBillingChunk,
  type DemoWorldV2PrimaryTab,
  type DemoWorldV2PublicCompetitionsChunk,
  type DemoWorldV2Referee,
  type DemoWorldV2Snapshot,
  type DemoWorldV2TournamentChunk,
} from "./demo-world-v2-contract";
import {
  demoWorldV2TabFromSearch,
  loadDemoWorldV2Core,
  loadDemoWorldV2Snapshot,
} from "./demo-world-v2-client-state";
import styles from "./demo-world.module.css";

type DemoWorldRenderableSnapshot = Pick<DemoWorldV2Snapshot, "activity" | "core" | "manifest" | "matches" | "players">;

const primaryTabs: Array<{ id: DemoWorldV2PrimaryTab; label: string }> = [
  { id: "inicio", label: "Inicio" },
  { id: "partido", label: "Partido" },
  { id: "mercado", label: "Mercado" },
  { id: "equipo", label: "Equipo" },
  { id: "perfil", label: "Perfil" },
];

const leagueTabs: Array<{ id: DemoWorldV2PrimaryTab; label: string }> = [
  { id: "liga", label: "Liga" },
  { id: "torneo", label: "Torneo" },
  { id: "competiciones", label: "Públicas" },
  { id: "configuracion", label: "Configuración" },
  { id: "clasificacion", label: "Clasificación" },
  { id: "jornadas", label: "Jornadas" },
  { id: "disciplina", label: "Disciplina" },
  { id: "club", label: "Club" },
  { id: "arbitros", label: "Árbitros" },
  { id: "planes", label: "Planes" },
];

const facetLabels = {
  defending: "DEF",
  dribbling: "REG",
  pace: "RIT",
  passing: "PAS",
  physical: "FIS",
  shooting: "TIR",
} as const;

const matchKindLabels: Record<DemoMatchKind, string> = {
  futbol11: "Fútbol 11",
  futbol7: "Fútbol 7",
  sala: "Fútbol sala",
};

const challengeStatusLabels: Record<DemoWorldChallenge["status"], string> = {
  accepted: "Aceptado",
  cancelled: "Cancelado",
  completed: "Finalizado",
  countered: "Contrapropuesta",
  pending: "Pendiente",
  rejected: "Rechazado",
};

const DEMO_WORLD_MARKET_PAGE_SIZE = 12;

function dateLabel(value: string, withYear = false) {
  return new Intl.DateTimeFormat("es-ES", {
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
    timeZone: "Europe/Madrid",
    ...(withYear ? { year: "numeric" } : {}),
  }).format(new Date(value));
}

function shortDateLabel(value: string) {
  return new Intl.DateTimeFormat("es-ES", {
    day: "2-digit",
    month: "short",
    timeZone: "Europe/Madrid",
  }).format(new Date(value));
}

function initials(name: string) {
  return name.split(/\s+/).slice(0, 2).map((part) => part[0] ?? "").join("").toUpperCase();
}

function ratingScore(player: DemoWorldPlayer) {
  return player.rating.currentOverall === null ? "POR" : Math.round(player.rating.currentOverall);
}

function playerWithDemoCosmetics(player: DemoWorldPlayer, equippedCosmeticKeys: string[]) {
  const cosmetics = equippedCosmeticKeys.reduce((loadout, cosmeticKey) => {
    const item = catalogEntry(cosmeticKey);
    return item && !item.prototype ? withCosmeticKey(loadout, item.slot, item.key) : loadout;
  }, player.cosmetics);
  return { ...player, cosmetics };
}

function previewSnapshot(manifest: DemoWorldV2Manifest, core: DemoWorldCoreChunk): DemoWorldRenderableSnapshot {
  return {
    activity: {
      achievements: [],
      notifications: core.preview.notifications,
      rewardBoxes: [],
      teamRewardMappings: [],
    },
    core,
    manifest,
    matches: { attendance: [], challenges: [], matches: core.preview.matches },
    players: { players: core.preview.players },
  };
}

function PlayerCard({ compact = false, onClick, player }: { compact?: boolean; onClick?: () => void; player: DemoWorldPlayer }) {
  const card = (
    <PlayerCosmeticCard
      ariaLabel={`Ficha de ${player.name}`}
      className={`${styles.playerCard}${compact ? ` ${styles.compactPlayerCard}` : ""}`}
      facets={Object.entries(player.rating.currentFacets).map(([key, value]) => ({
        key,
        label: facetLabels[key as keyof typeof facetLabels],
        value: Math.round(value),
      }))}
      featuredAchievement={player.featuredAchievementKey ? {
        achievementKey: player.featuredAchievementKey,
        grantId: `demo_badge_${player.id}`,
        rarity: "rare",
        title: player.featuredAchievementKey.includes("hat_tricks") ? "Hat-trick" : "Habitual",
      } : null}
      loadout={player.cosmetics}
      meta={`${player.appearances} PJ · ${player.goals} G`}
      name={player.name}
      photoAlt={`Avatar ficticio de ${player.name}`}
      photoSrc={demoAvatarDataUri(player.name, player.avatarHue)}
      position={player.position.abbreviation}
      score={ratingScore(player)}
    />
  );
  if (!onClick) return card;
  return <button className={styles.cardButton} type="button" onClick={onClick} aria-label={`Abrir ficha de ${player.name}`}>{card}</button>;
}

function TeamIdentity({ compact = false, team }: { compact?: boolean; team: DemoWorldTeam }) {
  return (
    <div className={`${styles.teamIdentity}${compact ? ` ${styles.teamIdentityCompact}` : ""}`}>
      <TeamShieldView
        catalog={TEAM_SHIELD_RENDER_CATALOG}
        config={team.shield}
        label={`Escudo de ${team.name}`}
        size={compact ? 48 : 82}
      />
      <span>
        <strong>{team.name}</strong>
        <small>{team.publicLocation}</small>
      </span>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number | string }) {
  return <span className={styles.stat}><strong>{value}</strong><small>{label}</small></span>;
}

function EmptyState({ body, title }: { body: string; title: string }) {
  return <div className={styles.emptyState}><strong>{title}</strong><p>{body}</p></div>;
}

function LoadingWorld({ manifest }: { manifest: DemoWorldV2Manifest }) {
  return (
    <main className={styles.shell} data-demo-world="loading">
      <div className={styles.loadingPanel} role="status">
        <span className={styles.loadingMark}>IQ</span>
        <strong>Preparando el Mundo Demo</strong>
        <p>{manifest.counts.teams} equipos y {manifest.counts.players} jugadores ficticios.</p>
      </div>
    </main>
  );
}

function DemoHeader({
  activeTab,
  manifest,
  onReset,
  onTab,
  perspective,
  perspectives,
  setPerspective,
}: {
  activeTab: DemoWorldV2PrimaryTab;
  manifest: DemoWorldV2Manifest;
  onReset: () => void;
  onTab: (tab: DemoWorldV2PrimaryTab) => void;
  perspective: DemoWorldPerspective;
  perspectives: DemoWorldPerspective[];
  setPerspective: (perspectiveId: DemoWorldPerspective["id"]) => void;
}) {
  const domainNavRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const navigation = domainNavRef.current;
    const activeControl = navigation?.querySelector<HTMLElement>('[aria-current="page"]');
    if (!navigation || !activeControl || navigation.scrollWidth <= navigation.clientWidth + 2) return;
    activeControl.scrollIntoView({ behavior: "auto", block: "nearest", inline: "center" });
  }, [activeTab]);

  return (
    <>
      <div className={styles.demoBanner} data-tour-target="demo-mode-banner">
        <span><b>Mundo Demo</b> · datos ficticios · temporada {manifest.season}</span>
        <span className={styles.bannerActions}>
          <button type="button" onClick={onReset}>Reiniciar</button>
          <Link href="/">Salir</Link>
        </span>
      </div>
      <header className={styles.header}>
        <Link className={styles.brand} href="/demo" aria-label="Pachangas IQ Mundo Demo">
          <span>PIQ</span>
          <strong>Pachangas IQ</strong>
        </Link>
        <nav className={styles.desktopNav} aria-label="Navegación del Mundo Demo">
          {primaryTabs.map((tab) => (
            <button aria-current={activeTab === tab.id ? "page" : undefined} key={tab.id} type="button" onClick={() => onTab(tab.id)}>
              {tab.label}
            </button>
          ))}
        </nav>
        <label className={styles.perspectivePicker} data-tour-target="demo-perspective">
          <span>Perspectiva</span>
          <select value={perspective.id} onChange={(event) => setPerspective(event.target.value as DemoWorldPerspective["id"])}>
            {perspectives.map((entry) => <option key={entry.id} value={entry.id}>{entry.label}</option>)}
          </select>
        </label>
      </header>
      <nav className={styles.domainNav} aria-label="Liga, Clubs y árbitros del Mundo Demo" ref={domainNavRef}>
        {leagueTabs.map((tab) => (
          <button aria-current={activeTab === tab.id ? "page" : undefined} key={tab.id} type="button" onClick={() => onTab(tab.id)}>
            {tab.label}
          </button>
        ))}
      </nav>
    </>
  );
}

function WorldHome({
  currentPlayer,
  currentTeam,
  notifications,
  onMatch,
  onPlayer,
  onTab,
  perspective,
  snapshot,
  teamMatches,
}: {
  currentPlayer: DemoWorldPlayer;
  currentTeam: DemoWorldTeam | null;
  notifications: DemoWorldNotification[];
  onMatch: (matchId: string) => void;
  onPlayer: (playerId: string) => void;
  onTab: (tab: DemoWorldV2PrimaryTab) => void;
  perspective: DemoWorldPerspective;
  snapshot: DemoWorldRenderableSnapshot;
  teamMatches: DemoWorldMatch[];
}) {
  const upcoming = teamMatches.filter((match) => match.status === "scheduled").sort((left, right) => Date.parse(left.date) - Date.parse(right.date));
  const history = teamMatches.filter((match) => match.status === "finalized").sort((left, right) => Date.parse(right.date) - Date.parse(left.date));
  const venueById = new Map(snapshot.core.venues.map((venue) => [venue.id, venue]));
  return (
    <div className={styles.pageStack} data-tour-target="demo-home">
      <section className={styles.identityBand}>
        <div>
          <span className={styles.eyebrow}>{perspective.label}</span>
          <h1>{currentTeam?.name ?? "Explora antes de elegir equipo"}</h1>
          <p>{currentTeam?.identity ?? "Mercado, partidos públicos y equipos retables sin crear una cuenta real."}</p>
          <div className={styles.inlineActions}>
            <button className={styles.primaryButton} type="button" onClick={() => onTab(currentTeam ? "partido" : "mercado")}>{currentTeam ? "Ver próximo partido" : "Explorar Mercado"}</button>
            <button type="button" onClick={() => onPlayer(currentPlayer.id)}>Abrir mi ficha</button>
          </div>
        </div>
        <div className={styles.identityVisual}>
          {currentTeam ? <TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={currentTeam.shield} label={`Escudo de ${currentTeam.name}`} size={210} /> : <PlayerCard player={currentPlayer} onClick={() => onPlayer(currentPlayer.id)} />}
        </div>
        <div className={styles.identityStats}>
          {currentTeam ? (
            <>
              <Stat label="Partidos" value={currentTeam.stats.matchesPlayed} />
              <Stat label="Retos" value={currentTeam.stats.challengesPlayed} />
              <Stat label="Victorias" value={currentTeam.stats.challengeWins} />
              <Stat label="Plantilla" value={currentTeam.memberCount} />
            </>
          ) : (
            <>
              <Stat label="Equipos" value={snapshot.manifest.counts.teams} />
              <Stat label="Partidos" value={snapshot.manifest.counts.matches} />
              <Stat label="Retos" value={snapshot.manifest.counts.challenges} />
              <Stat label="Jugadores" value={snapshot.manifest.counts.players} />
            </>
          )}
        </div>
      </section>

      <section className={styles.sectionBand} data-tour-target="demo-upcoming-matches">
        <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Agenda</span><h2>Próximos partidos</h2></div><button type="button" onClick={() => onTab("partido")}>Ver partido</button></div>
        <div className={styles.horizontalRail}>
          {upcoming.slice(0, 8).map((match) => (
            <button className={styles.matchTile} key={match.id} type="button" onClick={() => onMatch(match.id)}>
              <span>{shortDateLabel(match.date)} · {matchKindLabels[match.kind]}</span>
              <strong>{match.homeLabel}<b>vs</b>{match.awayLabel}</strong>
              <small>{venueById.get(match.venueId)?.label} · {match.publicOpenSlots} plazas</small>
            </button>
          ))}
          {!upcoming.length ? <EmptyState title="Sin próximos partidos" body="Esta perspectiva no tiene una agenda propia todavía." /> : null}
        </div>
      </section>

      <section className={styles.sectionBand}>
        <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Memoria</span><h2>Historias de la temporada</h2></div><span>{snapshot.core.stories.length} relatos conectados</span></div>
        <div className={styles.storyGrid}>
          {snapshot.core.stories.slice(0, 6).map((story) => (
            <article className={styles.storyItem} key={story.id}>
              <span>{shortDateLabel(story.date)} · {story.type}</span>
              <strong>{story.title}</strong>
              <p>{story.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.sectionBand}>
        <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Actividad</span><h2>Avisos recientes</h2></div><button type="button" onClick={() => onTab("perfil")}>Abrir avisos</button></div>
        <div className={styles.notificationStrip}>
          {notifications.slice(0, 4).map((notification) => (
            <article key={notification.id}><span data-category={notification.category}>{notification.category}</span><strong>{notification.title}</strong><p>{notification.body}</p></article>
          ))}
        </div>
      </section>

      <section className={styles.sectionBand}>
        <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Histórico</span><h2>Últimos resultados</h2></div></div>
        <div className={styles.horizontalRail}>
          {history.slice(0, 10).map((match) => (
            <button className={styles.resultTile} key={match.id} type="button" onClick={() => onMatch(match.id)}>
              <span>{shortDateLabel(match.date)}</span>
              <strong>{match.homeLabel}<b>{match.result?.home ?? "-"} : {match.result?.away ?? "-"}</b>{match.awayLabel}</strong>
              <small>{matchKindLabels[match.kind]}</small>
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

function PlayerToken({ onClick, player, side }: { onClick: () => void; player: DemoWorldPlayer; side: "away" | "home" }) {
  return (
    <button className={styles.playerToken} data-side={side} type="button" onClick={onClick}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img alt="" src={demoAvatarDataUri(player.name, player.avatarHue)} />
      <span><b>{player.position.abbreviation}</b>{player.name.split(" ")[0]}</span>
    </button>
  );
}

function MatchView({
  currentPlayer,
  currentTeam,
  match,
  onLocalAttendance,
  onMatch,
  onPlayer,
  perspective,
  session,
  setMessage,
  snapshot,
  teamMatches,
}: {
  currentPlayer: DemoWorldPlayer;
  currentTeam: DemoWorldTeam | null;
  match: DemoWorldMatch | null;
  onLocalAttendance: (status: "duda" | "no" | "voy") => void;
  onMatch: (matchId: string) => void;
  onPlayer: (playerId: string) => void;
  perspective: DemoWorldPerspective;
  session: DemoWorldSessionState;
  setMessage: (message: string) => void;
  snapshot: DemoWorldRenderableSnapshot;
  teamMatches: DemoWorldMatch[];
}) {
  const [pane, setPane] = useState<DemoWorldMatchPane>("proximo");
  const visiblePane = demoWorldMatchPaneForRole(pane, perspective.role);
  const playerById = useMemo(() => new Map(snapshot.players.players.map((player) => [player.id, player])), [snapshot]);
  const venue = match ? snapshot.core.venues.find((entry) => entry.id === match.venueId) : null;
  const matchPanes = perspective.role === "admin"
    ? ["proximo", "alineacion", "resultado", "historico", "admin"] as const
    : ["proximo", "alineacion", "resultado", "historico"] as const;
  const history = teamMatches.filter((entry) => entry.status === "finalized").sort((left, right) => Date.parse(right.date) - Date.parse(left.date));
  const attendance = match ? session.attendanceByMatch[match.id] : undefined;
  if (!match) return <EmptyState title="Sin partido seleccionado" body="Elige un partido público desde Mercado." />;

  return (
    <div className={styles.managerLayout} data-match-pane={visiblePane} data-tour-target="demo-match">
      <aside className={styles.sideSubnav} aria-label="Secciones del partido">
        <div className={styles.sideTitle}><span>Partido</span><strong>{match.status === "finalized" ? "Histórico" : "Activo"}</strong></div>
        {matchPanes.map((entry) => (
          <button aria-current={visiblePane === entry ? "page" : undefined} key={entry} type="button" onClick={() => setPane(entry)}>
            {entry === "proximo" ? (match.status === "finalized" ? "Partido" : "Próximo") : entry === "alineacion" ? "Alineación" : entry === "resultado" ? "Resultado" : entry === "historico" ? "Histórico" : "Admin"}
          </button>
        ))}
        <div className={styles.sideMeta}>
          <span>{matchKindLabels[match.kind]}</span>
          <span>rev. {match.revision}</span>
          <small>Snapshot congelado</small>
        </div>
      </aside>
      <section className={styles.managerContent}>
        <div className={styles.matchContext}>
          <div><span className={styles.eyebrow}>{match.status === "finalized" ? "Partido finalizado" : "Próximo partido"}</span><h1>{match.title}</h1></div>
          <span>{dateLabel(match.date)} · {venue?.label}</span>
        </div>

        {visiblePane === "proximo" ? (
          <div className={styles.nextMatchGrid}>
            <div className={styles.scoreboard}>
              <span>{match.homeLabel}</span>
              <strong>{match.result ? `${match.result.home} : ${match.result.away}` : "VS"}</strong>
              <span>{match.awayLabel}</span>
              <small>{dateLabel(match.date, true)}</small>
            </div>
            <div className={styles.matchFacts}>
              <Stat label="Confirmados" value={match.confirmedPlayerIds.length + (attendance === "voy" && !match.confirmedPlayerIds.includes(currentPlayer.id) ? 1 : 0)} />
              <Stat label="Reservas" value={match.reservePlayerIds.length} />
              <Stat label="Plazas" value={match.publicOpenSlots} />
              <Stat label="Modalidad" value={matchKindLabels[match.kind].replace("Fútbol ", "F-")} />
            </div>
            {match.status === "scheduled" && perspective.role === "player" && currentTeam ? (
              <div className={styles.attendanceControl} data-tour-target="demo-attendance">
                <div><strong>Mi asistencia</strong><small>Esta elección solo vive en esta sesión demo.</small></div>
                <div role="group" aria-label="Asistencia simulada">
                  {(["voy", "duda", "no"] as const).map((status) => <button aria-pressed={attendance === status} key={status} type="button" onClick={() => onLocalAttendance(status)}>{status === "voy" ? "Voy" : status === "duda" ? "Duda" : "No voy"}</button>)}
                </div>
              </div>
            ) : null}
            <div className={styles.rosterColumns}>
              {(["home", "away"] as const).map((side) => {
                const ids = side === "home" ? match.homePlayerIds : match.awayPlayerIds;
                return <div key={side}><strong>{side === "home" ? match.homeLabel : match.awayLabel}</strong>{ids.map((playerId) => {
                  const player = playerById.get(playerId);
                  return player ? <button key={playerId} type="button" onClick={() => onPlayer(playerId)}><span>{player.position.abbreviation}</span>{player.name}<b>{Math.round(player.rating.currentOverall ?? 0) || "POR"}</b></button> : null;
                })}</div>;
              })}
            </div>
          </div>
        ) : null}

        {visiblePane === "alineacion" ? (
          <div className={styles.pitchWrap}>
            <div className={styles.pitch} data-tour-target="demo-lineup">
              <span className={styles.pitchCenterLine} aria-hidden="true" />
              <span className={styles.pitchCircle} aria-hidden="true" />
              <span className={`${styles.pitchArea} ${styles.pitchAreaLeft}`} aria-hidden="true" />
              <span className={`${styles.pitchArea} ${styles.pitchAreaRight}`} aria-hidden="true" />
              <div className={`${styles.pitchSide} ${styles.pitchHome}`}>
                {match.homePlayerIds.map((playerId) => {
                  const player = playerById.get(playerId);
                  return player ? <PlayerToken key={playerId} onClick={() => onPlayer(playerId)} player={player} side="home" /> : null;
                })}
              </div>
              <div className={`${styles.pitchSide} ${styles.pitchAway}`}>
                {match.awayPlayerIds.map((playerId) => {
                  const player = playerById.get(playerId);
                  return player ? <PlayerToken key={playerId} onClick={() => onPlayer(playerId)} player={player} side="away" /> : null;
                })}
              </div>
              <div className={styles.balanceMeter}><span>Equilibrio del snapshot</span><strong>{Math.abs((match.homePlayerIds.reduce((sum, id) => sum + (playerById.get(id)?.rating.currentOverall ?? 60), 0) / Math.max(1, match.homePlayerIds.length)) - (match.awayPlayerIds.reduce((sum, id) => sum + (playerById.get(id)?.rating.currentOverall ?? 60), 0) / Math.max(1, match.awayPlayerIds.length))) < 3 ? "Igualado" : "Ligera ventaja"}</strong></div>
            </div>
            <p className={styles.readOnlyNote}>{match.status === "finalized" ? "Alineación histórica: posiciones y niveles quedan fijados en este partido." : "Toca una ficha para verla. En demo la alineación no modifica el servidor."}</p>
          </div>
        ) : null}

        {visiblePane === "resultado" ? (
          <div className={styles.resultLayout} data-tour-target="demo-result">
            <div className={styles.largeScore}>
              <span>{match.homeLabel}</span><strong>{match.result ? `${match.result.home} : ${match.result.away}` : "Pendiente"}</strong><span>{match.awayLabel}</span><small>{dateLabel(match.date, true)}</small>
            </div>
            <div className={styles.scorerList}>
              <h2>Goleadores</h2>
              {match.scorers.length ? match.scorers.map((scorer) => {
                const player = playerById.get(scorer.playerId);
                return player ? <button key={`${scorer.playerId}-${scorer.side}`} type="button" onClick={() => onPlayer(player.id)}><span>{scorer.side === "home" ? match.homeLabel : match.awayLabel}</span><strong>{player.name}</strong><b>{scorer.goals}</b></button> : null;
              }) : <EmptyState title="Marcador pendiente" body="Los goleadores aparecerán cuando el resultado esté confirmado." />}
            </div>
          </div>
        ) : null}

        {visiblePane === "historico" ? (
          <div className={styles.historyGrid}>
            {history.slice(0, 24).map((entry) => <button key={entry.id} type="button" onClick={() => onMatch(entry.id)}><span>{shortDateLabel(entry.date)} · {matchKindLabels[entry.kind]}</span><strong>{entry.homeLabel}<b>{entry.result?.home} : {entry.result?.away}</b>{entry.awayLabel}</strong></button>)}
          </div>
        ) : null}

        {visiblePane === "admin" && perspective.role === "admin" ? (
          <div className={styles.adminTools} data-tour-target="demo-admin">
            <div><span className={styles.eyebrow}>Simulación local</span><h2>Herramientas del partido</h2><p>Estos controles enseñan el flujo de admin, pero no ejecutan RPC ni cambian datos reales.</p></div>
            <div className={styles.adminActionGrid}>
              {demoWorldMatchAdminActions(match.status).map((label) => <button key={label} type="button" onClick={() => setMessage(`${label}: acción simulada en memoria.`)}>{label}<small>Solo demo</small></button>)}
            </div>
          </div>
        ) : null}
      </section>
    </div>
  );
}

function MarketView({
  currentPlayer,
  onMatch,
  onPlayer,
  onTeam,
  perspective,
  setMessage,
  snapshot,
}: {
  currentPlayer: DemoWorldPlayer;
  onMatch: (matchId: string) => void;
  onPlayer: (playerId: string) => void;
  onTeam: (teamId: string) => void;
  perspective: DemoWorldPerspective;
  setMessage: (message: string) => void;
  snapshot: DemoWorldRenderableSnapshot;
}) {
  const [pane, setPane] = useState<"equipos" | "jugadores" | "partidos" | "retos">("jugadores");
  const [query, setQuery] = useState("");
  const [visiblePlayerCount, setVisiblePlayerCount] = useState(DEMO_WORLD_MARKET_PAGE_SIZE);
  const normalizedQuery = query.trim().toLocaleLowerCase("es");
  const marketPlayers = snapshot.players.players.filter((player) => player.market.openToGuest && player.id !== currentPlayer.id && (!normalizedQuery || `${player.name} ${player.position.label} ${player.market.zones.join(" ")}`.toLocaleLowerCase("es").includes(normalizedQuery)));
  const publicMatches = snapshot.matches.matches.filter((match) => match.status === "scheduled" && match.publicOpenSlots > 0);
  const challenges = snapshot.matches.challenges.slice().sort((left, right) => Date.parse(right.date) - Date.parse(left.date));
  const teams = snapshot.core.teams.filter((team) => team.openToChallenges && (!normalizedQuery || `${team.name} ${team.publicLocation} ${team.territory}`.toLocaleLowerCase("es").includes(normalizedQuery)));

  return (
    <div className={styles.managerLayout} data-market-pane={pane} data-tour-target="demo-market">
      <aside className={styles.sideSubnav} aria-label="Secciones de Mercado">
        <div className={styles.sideTitle}><span>Mercado</span><strong>Mundo Demo</strong></div>
        {(["jugadores", "partidos", "retos", "equipos"] as const).map((entry) => <button aria-current={pane === entry ? "page" : undefined} key={entry} type="button" onClick={() => setPane(entry)}>{entry[0].toUpperCase() + entry.slice(1)}</button>)}
        {perspective.role === "admin" ? <button type="button" onClick={() => setMessage("Configuración de Mercado: simulada en memoria.")}>Configurar</button> : null}
        <div className={styles.sideMeta}><span>{snapshot.manifest.counts.players} jugadores</span><span>{snapshot.manifest.counts.teams} equipos</span><small>Datos públicos ficticios</small></div>
      </aside>
      <section className={styles.managerContent}>
        <div className={styles.marketHeader}><div><span className={styles.eyebrow}>Explorar</span><h1>Mercado</h1></div><Link href="/">Volver a Pachangas IQ</Link></div>
        {pane === "jugadores" ? <div className={styles.marketMatchFilter}>Filtrado por perfil demo: <strong>{currentPlayer.position.label}</strong> · {currentPlayer.market.zones.join(" / ")}</div> : null}
        <label className={styles.searchLine}><span>Buscar</span><input value={query} onChange={(event) => { setQuery(event.target.value); setVisiblePlayerCount(DEMO_WORLD_MARKET_PAGE_SIZE); }} placeholder={pane === "jugadores" ? "Nombre, posición o zona" : "Equipo o territorio"} /></label>

        {pane === "jugadores" ? (
          <>
            <div className={styles.playerMarketGrid}>{marketPlayers.slice(0, visiblePlayerCount).map((player) => <div className={styles.marketPlayer} key={player.id}><PlayerCard compact onClick={() => onPlayer(player.id)} player={player} /><div><strong>{player.name}</strong><span>{player.position.label} · {player.market.zones[0]}</span><small>{player.market.availability}</small>{canDemoWorldInvite(perspective.role) ? <button type="button" onClick={() => setMessage(`Invitación a ${player.name}: simulada, no enviada.`)}>Invitar</button> : null}</div></div>)}</div>
            {visiblePlayerCount < marketPlayers.length ? <div className={styles.marketPager}><span>{Math.min(visiblePlayerCount, marketPlayers.length)} de {marketPlayers.length}</span><button type="button" onClick={() => setVisiblePlayerCount((current) => current + DEMO_WORLD_MARKET_PAGE_SIZE)}>Mostrar más</button></div> : null}
          </>
        ) : null}
        {pane === "partidos" ? (
          <div className={styles.publicMatchGrid}>{publicMatches.map((match) => <button className={styles.publicMatch} key={match.id} type="button" onClick={() => onMatch(match.id)}><span>{dateLabel(match.date)} · {matchKindLabels[match.kind]}</span><strong>{match.homeLabel}<b>vs</b>{match.awayLabel}</strong><small>{snapshot.core.venues.find((venue) => venue.id === match.venueId)?.publicLocation} · {match.publicOpenSlots} plazas</small></button>)}</div>
        ) : null}
        {pane === "retos" ? (
          <div className={styles.challengeGrid}>{challenges.map((challenge) => {
            const home = snapshot.core.teams.find((team) => team.id === challenge.homeTeamId)!;
            const away = snapshot.core.teams.find((team) => team.id === challenge.awayTeamId)!;
            return <article className={styles.challengeItem} key={challenge.id}><span data-status={challenge.status}>{challengeStatusLabels[challenge.status]}</span><div><TeamIdentity compact team={home} /><b>vs</b><TeamIdentity compact team={away} /></div><p>{challenge.message}</p><small>{dateLabel(challenge.date)} · {matchKindLabels[challenge.proposedKind]}</small>{challenge.matchId ? <button type="button" onClick={() => onMatch(challenge.matchId!)}>Abrir partido</button> : null}</article>;
          })}</div>
        ) : null}
        {pane === "equipos" ? (
          <div className={styles.teamMarketGrid}>{teams.map((team) => <button key={team.id} type="button" onClick={() => onTeam(team.id)}><TeamIdentity team={team} /><p>{team.identity}</p><span>{team.stats.challengesPlayed} retos · {team.rankingLabel}</span></button>)}</div>
        ) : null}
      </section>
    </div>
  );
}

function TeamView({
  currentTeam,
  onPlayer,
  onTeam,
  selectedTeam,
  snapshot,
}: {
  currentTeam: DemoWorldTeam | null;
  onPlayer: (playerId: string) => void;
  onTeam: (teamId: string) => void;
  selectedTeam: DemoWorldTeam;
  snapshot: DemoWorldRenderableSnapshot;
}) {
  const [pane, setPane] = useState<"escudo" | "logros" | "plantilla" | "ranking">("ranking");
  const [rankingShowcase, setRankingShowcase] = useState<DemoWorldRankingShowcaseId>("my-rank");
  const roster = snapshot.players.players.filter((player) => player.teamId === selectedTeam.id).sort((left, right) => (right.rating.currentOverall ?? 0) - (left.rating.currentOverall ?? 0));
  const achievements = snapshot.activity.achievements.filter((achievement) => achievement.subjectId === selectedTeam.id);
  return (
    <div className={styles.managerLayout} data-team-pane={pane} data-tour-target="demo-team">
      <aside className={styles.sideSubnav} aria-label="Secciones de Equipo">
        <div className={styles.sideTitle}><span>Equipo</span><strong>{selectedTeam.name}</strong></div>
        {(["ranking", "plantilla", "logros", "escudo"] as const).map((entry) => <button aria-current={pane === entry ? "page" : undefined} key={entry} type="button" onClick={() => setPane(entry)}>{entry[0].toUpperCase() + entry.slice(1)}</button>)}
        <div className={styles.sideMeta}><span>{selectedTeam.territory}</span><span>{selectedTeam.memberCount} jugadores</span><small>{currentTeam?.id === selectedTeam.id ? "Tu equipo demo" : "Equipo visitado"}</small></div>
      </aside>
      <section className={styles.managerContent}>
        <div className={styles.teamViewHeader}><TeamIdentity team={selectedTeam} /><label><span>Cambiar equipo</span><select value={selectedTeam.id} onChange={(event) => onTeam(event.target.value)}>{snapshot.core.teams.map((team) => <option key={team.id} value={team.id}>{team.name}</option>)}</select></label></div>
        {pane === "ranking" ? (
          <div className={styles.provincialRanking}>
            <div className={styles.rankingIntro}>
              <div><span className={styles.eyebrow}>Ranking Provincial Demo</span><h1>Season Score V3</h1><p>Read model congelado con la misma fórmula y estados públicos que el producto. No concede TOPS ni premios.</p></div>
              <span>Premios provinciales OFF</span>
            </div>
            <div className={styles.rankingShowcases} aria-label="Casos de ranking simulados">
              {([
                ["my-rank", "Mi #27"],
                ["ineligible", "No elegible"],
                ["provisional", "Provisional"],
                ["pending-review", "Pendiente"],
              ] as Array<[DemoWorldRankingShowcaseId, string]>).map(([id, label]) => (
                <button aria-pressed={rankingShowcase === id} key={id} type="button" onClick={() => setRankingShowcase(id)}>{label}</button>
              ))}
            </div>
            <ProvincialRankingBoard
              embedded
              ownRank={snapshot.core.provincialRanking.showcases[rankingShowcase]}
              ranking={snapshot.core.provincialRanking.ranking}
            />
          </div>
        ) : null}
        {pane === "plantilla" ? <div className={styles.rosterCardGrid}>{roster.map((player) => <PlayerCard compact key={player.id} onClick={() => onPlayer(player.id)} player={player} />)}</div> : null}
        {pane === "logros" ? <AchievementList achievements={achievements} /> : null}
        {pane === "escudo" ? (
          <div className={styles.shieldRoom}>
            <TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={selectedTeam.shield} label={`Escudo de ${selectedTeam.name}`} size={210} />
            <div><span className={styles.eyebrow}>Identidad conseguida</span><h1>{selectedTeam.name}</h1><p>{selectedTeam.identity}</p><div className={styles.cosmeticList}>{selectedTeam.unlockedCosmeticKeys.map((key) => <span key={key}>{TEAM_SHIELD_RENDER_CATALOG.find((item) => item.key === key)?.name ?? key}</span>)}</div><small>Premium Ball permanece inactivo. Ninguna propuesta del laboratorio Premium Art forma parte del inventario.</small></div>
          </div>
        ) : null}
      </section>
    </div>
  );
}

function AchievementList({ achievements }: { achievements: DemoWorldAchievement[] }) {
  return <div className={styles.achievementGrid}>{achievements.length ? achievements.map((achievement) => <article key={achievement.id} data-rarity={achievement.rarity}><span>{achievement.rarity}</span><strong>{achievement.title}</strong><p>{achievement.description}</p><small>{achievement.evidence}</small></article>) : <EmptyState title="Sin logros en esta muestra" body="La demo no inventa un logro sin evidencia en el snapshot." />}</div>;
}

function ProfileView({
  currentPlayer,
  currentTeam,
  notifications,
  onEquipCosmetic,
  onOpenBox,
  onPerspective,
  onPlayer,
  onRead,
  perspective,
  perspectives,
  session,
  snapshot,
}: {
  currentPlayer: DemoWorldPlayer;
  currentTeam: DemoWorldTeam | null;
  notifications: DemoWorldNotification[];
  onEquipCosmetic: (cosmeticKey: string) => void;
  onOpenBox: (box: DemoWorldRewardBox) => void;
  onPerspective: (perspectiveId: DemoWorldPerspective["id"]) => void;
  onPlayer: (playerId: string) => void;
  onRead: (notificationId: string) => void;
  perspective: DemoWorldPerspective;
  perspectives: DemoWorldPerspective[];
  session: DemoWorldSessionState;
  snapshot: DemoWorldRenderableSnapshot;
}) {
  const [pane, setPane] = useState<"avisos" | "ficha" | "recompensas">("ficha");
  const achievements = snapshot.activity.achievements.filter((achievement) => achievement.subjectId === currentPlayer.id || (currentTeam && achievement.subjectId === currentTeam.id));
  const boxes = snapshot.activity.rewardBoxes.filter((box) => box.ownerId === currentPlayer.id || (currentTeam && box.ownerId === currentTeam.id));
  const attendance = snapshot.matches.attendance.filter((entry) => entry.playerId === currentPlayer.id);
  return (
    <div className={styles.managerLayout} data-profile-pane={pane} data-tour-target="demo-profile">
      <aside className={styles.sideSubnav} aria-label="Secciones de Perfil">
        <div className={styles.sideTitle}><span>Perfil</span><strong>{currentPlayer.name}</strong></div>
        {(["ficha", "recompensas", "avisos"] as const).map((entry) => <button aria-current={pane === entry ? "page" : undefined} key={entry} type="button" onClick={() => setPane(entry)}>{entry[0].toUpperCase() + entry.slice(1)}{entry === "avisos" ? <b>{notifications.filter((notification) => !session.readNotificationIds.includes(notification.id)).length}</b> : null}</button>)}
        <label className={styles.gamePerspectiveSelect}><span>Perspectiva</span><select aria-label="Perspectiva en modo juego" value={perspective.id} onChange={(event) => onPerspective(event.target.value as DemoWorldPerspective["id"])}>{perspectives.map((entry) => <option key={entry.id} value={entry.id}>{entry.label}</option>)}</select></label>
        <div className={styles.sideMeta}><span>{perspective.label}</span><span>{currentTeam?.name ?? "Sin equipo"}</span><small>Perfil ficticio</small></div>
      </aside>
      <section className={styles.managerContent}>
        {pane === "ficha" ? (
          <div className={styles.profileLayout}>
            <PlayerCard player={currentPlayer} />
            <div className={styles.profileDetails}><span className={styles.eyebrow}>Ficha universal demo</span><h1>{currentPlayer.name}</h1><p>{currentPlayer.market.publicBio}</p><div className={styles.profileStats}><Stat label="Partidos" value={currentPlayer.appearances} /><Stat label="Goles" value={currentPlayer.goals} /><Stat label="Asistencias" value={currentPlayer.assists} /><Stat label="Fiabilidad" value={`${currentPlayer.rating.reliability}%`} /></div><dl><div><dt>Posición</dt><dd>{currentPlayer.position.label}</dd></div><div><dt>Motor</dt><dd>{currentPlayer.rating.engineVersion}</dd></div><div><dt>Evaluadores</dt><dd>{currentPlayer.rating.evaluatorCount}</dd></div><div><dt>Zonas públicas</dt><dd>{currentPlayer.market.zones.join(" · ")}</dd></div></dl><div className={styles.attendanceSummary}><strong>Asistencia histórica</strong><span>{attendance.filter((entry) => entry.status === "played").length} jugados</span><span>{attendance.filter((entry) => entry.status === "excused_absence").length} bajas justificadas</span><span>{attendance.filter((entry) => entry.status === "late_cancellation").length} cancelaciones tardías</span><span>{attendance.filter((entry) => entry.status === "unexcused_no_show").length} no-show</span></div><small>La ficha usa el read model de Rating V2. La demo no recalcula ni persiste valoraciones.</small></div>
            <div className={styles.relatedPlayers}><h2>Compañeros</h2>{snapshot.players.players.filter((player) => player.teamId && player.teamId === currentPlayer.teamId && player.id !== currentPlayer.id).slice(0, 5).map((player) => <button key={player.id} type="button" onClick={() => onPlayer(player.id)}><span>{initials(player.name)}</span><strong>{player.name}</strong><small>{player.position.abbreviation} · {ratingScore(player)}</small></button>)}</div>
          </div>
        ) : null}
        {pane === "recompensas" ? (
          <div className={styles.rewardsLayout}>
            <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Economía demo</span><h1>Cajas y recompensas</h1></div><span>{boxes.filter((box) => box.state === "pending" && !session.openedBoxIds.includes(box.id)).length} pendientes</span></div>
            <div className={styles.boxGrid}>{boxes.map((box) => {
              const opened = box.state === "opened" || session.openedBoxIds.includes(box.id);
              const cosmetic = PLAYER_COSMETIC_CATALOG.find((item) => item.key === box.rewardCosmeticKey);
              const isNew = session.newCosmeticKeys.includes(box.rewardCosmeticKey);
              const equipped = session.equippedCosmeticKeys.includes(box.rewardCosmeticKey);
              return <article key={box.id} data-new={isNew || undefined} data-state={opened ? "opened" : "pending"}><span className={styles.boxGlyph}>IQ</span><div><small>{box.rarity}{isNew ? " · NEW" : ""}</small><strong>{opened ? cosmetic?.name ?? "Caja abierta" : "Caja pendiente"}</strong><p>{opened ? cosmetic?.description ?? box.rewardCosmeticKey : "Recompensa oculta hasta abrir"}</p></div>{!opened ? <button type="button" onClick={() => onOpenBox(box)}>Abrir demo</button> : cosmetic ? <button disabled={equipped} type="button" onClick={() => onEquipCosmetic(cosmetic.key)}>{equipped ? "Equipado" : "Equipar"}</button> : <span>Escudo</span>}</article>;
            })}</div>
            <AchievementList achievements={achievements} />
          </div>
        ) : null}
        {pane === "avisos" ? (
          <div className={styles.notificationsPage}>
            <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Centro de avisos</span><h1>Notificaciones</h1></div><span>{notifications.filter((notification) => !session.readNotificationIds.includes(notification.id)).length} sin leer</span></div>
            {notifications.map((notification) => {
              const read = session.readNotificationIds.includes(notification.id);
              return <button className={styles.notificationRow} data-read={read} key={notification.id} type="button" onClick={() => onRead(notification.id)}><span data-category={notification.category}>{notification.category}</span><div><strong>{notification.title}{notification.mandatory ? <b>Obligatorio</b> : null}</strong><p>{notification.body}</p><small>{dateLabel(notification.createdAt)}</small></div><i>{read ? "Leído" : "Nuevo"}</i></button>;
            })}
          </div>
        ) : null}
      </section>
    </div>
  );
}

function PlayerModal({ onClose, player }: { onClose: () => void; player: DemoWorldPlayer }) {
  return (
    <div className={styles.modalBackdrop} role="dialog" aria-modal="true" aria-label={`Ficha de ${player.name}`} onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}>
      <div className={styles.playerModal}>
        <button className={styles.closeButton} type="button" onClick={onClose} aria-label="Cerrar ficha">×</button>
        <PlayerCard player={player} />
        <div><span className={styles.eyebrow}>Ficha pública</span><h2>{player.name}</h2><p>{player.market.publicBio}</p><dl><div><dt>Posición</dt><dd>{player.position.label}</dd></div><div><dt>Partidos</dt><dd>{player.appearances}</dd></div><div><dt>Goles</dt><dd>{player.goals}</dd></div><div><dt>Fiabilidad</dt><dd>{player.rating.reliability}%</dd></div></dl><small>Sin teléfono, correo, dirección privada ni identidad de evaluadores.</small></div>
      </div>
    </div>
  );
}

function leagueExceptionLabel(match: DemoWorldV2Snapshot["competitions"]["matches"][number]) {
  if (match.lateArrivalStatus === "arrived_within_policy") return "Retraso resuelto";
  if (match.exceptionType === "postponed") return "Aplazado y jugado";
  if (match.exceptionType === "venue_changed") return "Cambio de sede";
  if (match.exceptionType === "no_show") return "Incomparecencia";
  if (match.exceptionType === "suspended_resumed") return "Suspendido y reanudado";
  return "Resultado oficial";
}

function LeagueOverviewView({
  onClub,
  onMatch,
  onTab,
  snapshot,
}: {
  onClub: (clubId: string) => void;
  onMatch: (matchId: string) => void;
  onTab: (tab: DemoWorldV2PrimaryTab) => void;
  snapshot: DemoWorldV2Snapshot;
}) {
  const league = snapshot.competitions;
  const teamById = new Map(snapshot.core.teams.map((team) => [team.id, team]));
  const clubByTeamId = new Map(snapshot.clubsReferees.clubs.flatMap((club) => club.teamIds.map((teamId) => [teamId, club] as const)));
  const exceptional = league.matches.filter((match) => match.exceptionType !== "none" || match.lateArrivalStatus !== null);
  return <div className={styles.leagueStack} data-demo-domain="league">
    <section className={styles.leagueHero}>
      <div>
        <span className={styles.eyebrow}>Liga privada · Simulation World verificado</span>
        <h1>{league.competition.name}</h1>
        <p>{league.competition.edition.name} · {league.competition.category.name} · {league.competition.group.name}</p>
        <div className={styles.inlineActions}>
          <button className={styles.primaryButton} type="button" onClick={() => onTab("clasificacion")}>Ver clasificación</button>
          <button type="button" onClick={() => onTab("jornadas")}>Abrir jornadas</button>
        </div>
      </div>
      <div className={styles.leagueMetrics}>
        <Stat label="Equipos" value={league.entries.length} />
        <Stat label="Jornadas" value={league.rounds.length} />
        <Stat label="Partidos" value={league.matches.length} />
        <Stat label="Oficiales" value={league.standingSnapshot.computedResults} />
      </div>
    </section>

    <section className={styles.sectionBand}>
      <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Participantes</span><h2>Equipos y Clubs</h2></div><span>Plantillas cerradas</span></div>
      <div className={styles.leagueTeamRail}>
        {league.entries.map((entry) => {
          const team = teamById.get(entry.teamId)!;
          const club = clubByTeamId.get(entry.teamId);
          return <button key={entry.id} type="button" onClick={() => club && onClub(club.id)}>
            <TeamIdentity compact team={team} />
            <small>{club ? club.name : "Equipo independiente"}</small>
          </button>;
        })}
      </div>
    </section>

    <section className={styles.sectionBand}>
      <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Calendario canónico</span><h2>15 partidos oficiales</h2></div><button type="button" onClick={() => onTab("jornadas")}>Cambiar jornada</button></div>
      <div className={styles.leagueMatchRail}>
        {league.matches.map((match) => <button key={match.id} type="button" onClick={() => onMatch(match.id)}>
          <span>J{match.roundNumber} · {shortDateLabel(match.scheduledStart)}</span>
          <strong>{teamById.get(match.homeTeamId)?.name}<b>{match.result.home} : {match.result.away}</b>{teamById.get(match.awayTeamId)?.name}</strong>
          <small>{match.venueLabel}</small>
        </button>)}
      </div>
    </section>

    <section className={styles.sectionBand}>
      <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>R4D</span><h2>Incidencias con trazabilidad</h2></div><span>{exceptional.length} historias</span></div>
      <div className={styles.incidentGrid}>
        {exceptional.map((match) => <button key={match.id} type="button" onClick={() => onMatch(match.id)}>
          <span>{leagueExceptionLabel(match)}</span>
          <strong>{teamById.get(match.homeTeamId)?.name} · {teamById.get(match.awayTeamId)?.name}</strong>
          <small>{match.lineage.length} pasos · rev. {match.officialDecision.revision}</small>
        </button>)}
      </div>
    </section>
  </div>;
}

const tournamentConstraintLabels: Record<string, string> = {
  POT_DISTRIBUTION: "Un equipo de cada bombo",
  SAME_CLUB_AVOIDANCE: "Separar equipos del mismo Club",
  TEAM_LEVEL_BALANCE: "Equilibrar nivel de los grupos",
};

type DemoTournamentPane = "arbitros" | "clasificacion" | "cuadro" | "disciplina" | "equipos" | "incidencias" | "jornadas" | "partidos" | "reglamento" | "resumen";

const demoTournamentPanes: Array<{ id: DemoTournamentPane; label: string }> = [
  { id: "resumen", label: "Resumen" },
  { id: "jornadas", label: "Jornadas" },
  { id: "partidos", label: "Partidos" },
  { id: "clasificacion", label: "Clasificación" },
  { id: "equipos", label: "Equipos" },
  { id: "disciplina", label: "Disciplina" },
  { id: "arbitros", label: "Árbitros" },
  { id: "incidencias", label: "Incidencias" },
  { id: "reglamento", label: "Reglamento" },
  { id: "cuadro", label: "Cuadro" },
];

const tournamentIncidentLabels = {
  DISPUTED_CORRECTED: "Disputa corregida",
  NONE: "Sin incidencia",
  NO_SHOW: "Incomparecencia",
  POSTPONED_RESCHEDULED: "Aplazado y reprogramado",
  SUSPENDED_RESUMED: "Suspendido y reanudado",
} as const;

const tournamentKnockoutResolutionLabels = {
  ADMINISTRATIVE_DECISION: "Decisión administrativa",
  EXTRA_TIME: "Prórroga",
  FORFEIT: "Incomparecencia",
  NO_SHOW: "Incomparecencia",
  PENALTY_SHOOTOUT: "Penaltis",
  SPORTING_RESULT: "Resultado deportivo",
} as const;

function demoTournamentGroupLabel(groupNumber: number) {
  return `Grupo ${String.fromCharCode(64 + groupNumber)}`;
}

function DemoTournamentView({ tournament }: { tournament: DemoWorldV2TournamentChunk }) {
  const [pane, setPane] = useState<DemoTournamentPane>("cuadro");
  const tournamentSubnavRef = useRef<HTMLElement>(null);
  const activeTournamentPaneRef = useRef<HTMLButtonElement>(null);
  const [outcomeIndex, setOutcomeIndex] = useState<0 | 1>(1);
  const [roundNumber, setRoundNumber] = useState(2);
  const [groupNumber, setGroupNumber] = useState(1);
  const [matchFilter, setMatchFilter] = useState<"ALL" | "OFFICIAL" | "SCHEDULED">("ALL");
  const outcome = tournament.drawOutcomes[outcomeIndex];
  const stage = tournament.groupStage;
  const knockout = tournament.knockout;
  const [selectedJourneyTeamId, setSelectedJourneyTeamId] = useState(knockout.podium.champion.id);
  const selectedJourney = knockout.teamJourneys.find(({ team }) => team.id === selectedJourneyTeamId)
    ?? knockout.teamJourneys[0];
  useEffect(() => {
    const rail = tournamentSubnavRef.current;
    const revealActivePane = () => {
      const activePane = activeTournamentPaneRef.current;
      if (!rail || !activePane) return;
      const railRect = rail.getBoundingClientRect();
      const activeRect = activePane.getBoundingClientRect();
      if (activeRect.left < railRect.left) rail.scrollLeft += activeRect.left - railRect.left;
      else if (activeRect.right > railRect.right) rail.scrollLeft += activeRect.right - railRect.right;
    };
    revealActivePane();
    if (!rail || typeof ResizeObserver === "undefined") return;
    const resizeObserver = new ResizeObserver(revealActivePane);
    resizeObserver.observe(rail);
    return () => resizeObserver.disconnect();
  }, [pane]);
  const groups = Array.from({ length: tournament.competition.groupCount }, (_, index) => ({
    number: index + 1,
    placements: outcome.placements
      .filter((placement) => placement.groupNumber === index + 1)
      .sort((left, right) => left.slotNumber - right.slotNumber),
  }));
  const roundMatches = stage.matches.filter((match) => match.roundNumber === roundNumber);
  const filteredMatches = stage.matches.filter((match) => matchFilter === "ALL" || match.status === matchFilter);
  const groupStandings = stage.standings
    .filter((standing) => standing.groupNumber === groupNumber)
    .sort((left, right) => left.position - right.position);
  const incidentMatches = stage.matches.filter((match) => match.incidentType !== "NONE");
  const teamStandings = new Map(stage.standings.map((standing) => [standing.team.id, standing]));
  const renderMatches = (matches: typeof stage.matches) => <div className={styles.tournamentMatchGrid}>
    {matches.map((match) => <article className={styles.tournamentMatchCard} key={match.matchKey}>
      <header>
        <span>{demoTournamentGroupLabel(match.groupNumber)} · J{match.roundNumber}</span>
        <b data-status={match.status}>{match.status === "OFFICIAL" ? "Oficial" : "Programado"}</b>
      </header>
      <div className={styles.tournamentMatchup}>
        <strong>{match.homeTeam.name}</strong>
        <span>{match.score ? `${match.score.home} : ${match.score.away}` : "VS"}</span>
        <strong>{match.awayTeam.name}</strong>
      </div>
      <footer>
        <span>{shortDateLabel(match.scheduledStart)} · {new Date(match.scheduledStart).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Madrid" })}</span>
        <span>{match.refereeNumber ? `Árbitro ${match.refereeNumber}` : "Sin árbitro"}</span>
        {match.incidentType !== "NONE" ? <em>{tournamentIncidentLabels[match.incidentType]}</em> : null}
      </footer>
    </article>)}
  </div>;
  const renderKnockoutNode = (node: typeof knockout.nodes[number]) => <article className={styles.tournamentKnockoutNode} data-resolution={node.resolutionKind} key={node.nodeKey}>
    <header><span>{node.nodeKey}</span><b>{tournamentKnockoutResolutionLabels[node.resolutionKind]}</b></header>
    <div data-winner={node.winnerTeamId === node.homeTeam.id}><strong>{node.homeTeam.name}</strong><b>{node.score.home}</b></div>
    <div data-winner={node.winnerTeamId === node.awayTeam.id}><strong>{node.awayTeam.name}</strong><b>{node.score.away}</b></div>
    {node.shootout ? <p>Penaltis · {node.shootout.home}-{node.shootout.away}</p> : node.extraTime ? <p>Prórroga · {node.extraTime.home}-{node.extraTime.away}</p> : null}
    <footer><span>{shortDateLabel(node.scheduledStart)}</span><span>{node.referee ? `Árbitro ${node.referee.refereeNumber}` : node.venueLabel}</span></footer>
  </article>;
  return <div className={styles.tournamentStack} data-demo-domain="tournament" data-demo-read-only="true">
    <section className={styles.tournamentHero}>
      <div>
        <span className={styles.eyebrow}>Demo World V2.6 · Torneo canónico completo</span>
        <h1>{tournament.competition.name}</h1>
        <p>Fase de grupos, cuadro eliminatorio, árbitros, disciplina y campeón confirmados por PostgreSQL.</p>
      </div>
      <div className={styles.tournamentMetrics}>
        <Stat label="Estado" value="Bloqueado" />
        <Stat label="Campeón" value={knockout.podium.champion.name} />
        <Stat label="Eliminatorias" value={knockout.nodes.length} />
        <Stat label="Partidos" value={tournament.nextPhase.tournamentMatches} />
      </div>
    </section>

    <nav ref={tournamentSubnavRef} className={styles.tournamentSubnav} aria-label="Secciones del Torneo">
      {demoTournamentPanes.map((item) => <button ref={pane === item.id ? activeTournamentPaneRef : undefined} aria-current={pane === item.id ? "page" : undefined} key={item.id} type="button" onClick={() => setPane(item.id)}>{item.label}</button>)}
    </nav>

    <main className={styles.tournamentPane}>
      {pane === "resumen" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>Cierre canónico</span><h2>Torneo completado</h2></div><strong>Cuadro bloqueado</strong></header>
        <div className={styles.tournamentOrganizerGrid}>
          <Stat label="Grupos" value={tournament.completionProof.officialMatches} />
          <Stat label="Eliminatorias" value={knockout.authority.activeMatches} />
          <Stat label="Históricos" value={knockout.authority.historicalMatches} />
          <Stat label="Correcciones" value={knockout.organizerDesk.correctionsWithImpact} />
          <Stat label="Sin resolver" value={knockout.organizerDesk.unresolvedNodes} />
          <Stat label="Snapshots" value={knockout.authority.completionSnapshots} />
        </div>
        <div className={styles.tournamentSummarySplit}>
          <section><h3>Final</h3>{knockout.nodes.filter(({ roundCode }) => roundCode === "FINAL").map(renderKnockoutNode)}</section>
          <section><h3>Podio</h3><div className={styles.tournamentCompactStandings}><div><span>1.º</span><strong>{knockout.podium.champion.name}</strong><b>Campeón</b></div><div><span>2.º</span><strong>{knockout.podium.runnerUp.name}</strong><b>Finalista</b></div><div><span>3.º</span><strong>{knockout.podium.thirdPlace.name}</strong><b>Podio</b></div></div></section>
        </div>
      </> : null}

      {pane === "jornadas" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>Calendario</span><h2>Jornada {roundNumber}</h2></div><span>{roundMatches.filter(({ status }) => status === "OFFICIAL").length}/8 oficiales</span></header>
        <div className={styles.tournamentRoundRail}>{[1, 2, 3].map((round) => <button aria-pressed={roundNumber === round} key={round} type="button" onClick={() => setRoundNumber(round)}>J{round}</button>)}</div>
        {renderMatches(roundMatches)}
      </> : null}

      {pane === "partidos" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>32 CanonicalMatches activos</span><h2>Partidos</h2></div><span>{filteredMatches.length + knockout.nodes.length} visibles</span></header>
        <div className={styles.tournamentRoundRail}>{(["ALL", "SCHEDULED", "OFFICIAL"] as const).map((filter) => <button aria-pressed={matchFilter === filter} key={filter} type="button" onClick={() => setMatchFilter(filter)}>{filter === "ALL" ? "Todos" : filter === "OFFICIAL" ? "Oficiales" : "Próximos"}</button>)}</div>
        {renderMatches(filteredMatches)}
        {matchFilter !== "SCHEDULED" ? <><h3 className={styles.tournamentSectionTitle}>Eliminatorias</h3><div className={styles.tournamentMatchGrid}>{knockout.nodes.map(renderKnockoutNode)}</div></> : null}
      </> : null}

      {pane === "clasificacion" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>R4C StandingSnapshot</span><h2>{demoTournamentGroupLabel(groupNumber)}</h2></div><span>Provisional · J2</span></header>
        <div className={styles.tournamentRoundRail}>{[1, 2, 3, 4].map((group) => <button aria-pressed={groupNumber === group} key={group} type="button" onClick={() => setGroupNumber(group)}>Grupo {String.fromCharCode(64 + group)}</button>)}</div>
        <div className={styles.tournamentStandingsWrap}><table><thead><tr><th>Pos</th><th>Equipo</th><th>PJ</th><th>G</th><th>E</th><th>P</th><th>GF</th><th>GC</th><th>DG</th><th>PTS</th></tr></thead><tbody>{groupStandings.map((row) => <tr data-qualified={row.qualificationZone} key={row.team.id}><td>{row.position}</td><td>{row.team.name}</td><td>{row.played}</td><td>{row.wins}</td><td>{row.draws}</td><td>{row.losses}</td><td>{row.goalsFor}</td><td>{row.goalsAgainst}</td><td>{row.goalDifference}</td><td><strong>{row.points}</strong></td></tr>)}</tbody></table></div>
        <p className={styles.tournamentCriteria}>Criterios: {groupStandings[0]?.criteria.join(" · ") || "Puntos · diferencia de goles · goles a favor"} · revisión {groupStandings[0]?.revision ?? 0}</p>
      </> : null}

      {pane === "equipos" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>ParticipantFreeze publicado</span><h2>16 equipos</h2></div><span>4 por grupo</span></header>
        <div className={styles.tournamentTeamGrid}>{groups.flatMap((group) => group.placements.map((placement) => { const standing = teamStandings.get(placement.team.id); return <article key={placement.team.id}><span>{demoTournamentGroupLabel(group.number)}</span><strong>{placement.team.name}</strong><small>{standing ? `${standing.position}.º · ${standing.points} pts` : `Bombo ${placement.potNumber}`}</small></article>; }))}</div>
      </> : null}

      {pane === "disciplina" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>R5</span><h2>Disciplina pública</h2></div><span>{stage.discipline.length} eventos</span></header>
        <div className={styles.tournamentEventList}>{stage.discipline.map((event, index) => <article key={`${event.team.id}-${index}`}><b data-card={event.cardType}>{event.cardType}</b><div><strong>{event.team.name}</strong><span>{event.playerLabel}</span></div><small>{event.status}</small></article>)}</div>
        <div className={styles.tournamentSanctionStrip}>{stage.sanctions.map((sanction, index) => <article key={`${sanction.team.id}-${index}`}><span>Sanción aplicable</span><strong>{sanction.team.name}</strong><small>{sanction.publicSummary} · {sanction.remainingUnits} {sanction.unitType}</small></article>)}</div>
        <div className={styles.tournamentSanctionStrip}><article><span>Aplicada en eliminatorias</span><strong>{knockout.discipline.team.name}</strong><small>{knockout.discipline.playerLabel} no fue elegible para la semifinal · Rating intacto</small></article></div>
      </> : null}

      {pane === "arbitros" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>Referee Assignments</span><h2>Árbitros</h2></div><span>{stage.referees.confirmedMatches} confirmados · {stage.referees.unassignedMatches} sin asignar</span></header>
        {renderMatches(stage.matches.filter((match) => match.refereeNumber !== undefined))}
      </> : null}

      {pane === "incidencias" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>R4D</span><h2>Incidencias resueltas</h2></div><span>{incidentMatches.length} historias</span></header>
        {renderMatches(incidentMatches)}
      </> : null}

      {pane === "reglamento" ? <>
        <header className={styles.tournamentToolbar}><div><span className={styles.eyebrow}>Sorteo y RuleRevision</span><h2>{outcome.mode === "HYBRID" ? "Sorteo híbrido publicado" : "Sorteo automático inicial"}</h2></div><div className={styles.tournamentRevisionSwitch} role="tablist" aria-label="Revisión del sorteo"><button aria-selected={outcomeIndex === 0} role="tab" type="button" onClick={() => setOutcomeIndex(0)}>Automática</button><button aria-selected={outcomeIndex === 1} role="tab" type="button" onClick={() => setOutcomeIndex(1)}>Híbrida</button></div></header>
        <div className={styles.tournamentAuditStrip}><span><small>Calidad</small><strong>{outcome.qualityScore.toFixed(1)}</strong></span><span><small>Hard</small><strong>{outcome.hardViolations}</strong></span><span><small>Overrides</small><strong>{outcome.manualOverrideCount}</strong></span><span><small>Seed</small><code>{outcome.seed}</code></span><span><small>Input</small><code>{outcome.inputChecksum.slice(0, 12)}</code></span><span><small>Resultado</small><code>{outcome.resultChecksum.slice(0, 12)}</code></span></div>
        <div className={styles.tournamentGroups}>{groups.map((group) => <article key={group.number}><header><span>{demoTournamentGroupLabel(group.number)}</span><small>4 equipos</small></header><div>{group.placements.map((placement) => <div className={placement.placementSource === "LOCKED" ? styles.tournamentLockedTeam : undefined} key={placement.team.id}><span className={styles.tournamentPot}>B{placement.potNumber}</span><strong>{placement.team.name}</strong><small>{placement.placementSource === "LOCKED" ? "Fijado" : `P${placement.slotNumber}`}</small></div>)}</div></article>)}</div>
        <div className={styles.tournamentRuleGrid}><section><h3>Reglas activas</h3>{tournament.constraints.map((constraint) => <p key={constraint.type}><span>{constraint.strength}</span><strong>{tournamentConstraintLabels[constraint.type] ?? constraint.type}</strong></p>)}</section><section><h3>Escenario rechazado</h3><strong>{tournament.conflict.errorCode}</strong><p>{tournament.conflict.explanation}</p></section></div>
      </> : null}

      {pane === "cuadro" ? <>
        <header className={styles.tournamentPaneHeader}><div><span className={styles.eyebrow}>R6C · Single leg</span><h2>Cuadro oficial</h2></div><span>8 clasificados · 8 partidos</span></header>
        <div className={styles.tournamentKnockoutWorkspace}>
          <div className={styles.tournamentKnockoutBoard} aria-label="Cuadro eliminatorio completo">
            <section><header>Cuartos</header>{knockout.nodes.filter(({ roundCode }) => roundCode === "QUARTERFINAL").map(renderKnockoutNode)}</section>
            <section><header>Semifinales</header>{knockout.nodes.filter(({ roundCode }) => roundCode === "SEMIFINAL").map(renderKnockoutNode)}</section>
            <section><header>Finales</header>{knockout.nodes.filter(({ roundCode }) => roundCode === "FINAL" || roundCode === "THIRD_PLACE").map(renderKnockoutNode)}</section>
          </div>
          <aside className={styles.tournamentKnockoutAside}>
            <div className={styles.tournamentChampion}><span>Campeón</span><strong>{knockout.podium.champion.name}</strong><small>{knockout.podium.runnerUp.name} · subcampeón</small></div>
            <div><span className={styles.eyebrow}>Recorrido por equipo</span><select aria-label="Equipo del recorrido" value={selectedJourney?.team.id} onChange={(event) => setSelectedJourneyTeamId(event.target.value)}>{knockout.teamJourneys.map((journey) => <option key={journey.team.id} value={journey.team.id}>{journey.team.name}</option>)}</select></div>
            {selectedJourney ? <div className={styles.tournamentJourney}><strong>{selectedJourney.status.replaceAll("_", " ")}</strong><span>{selectedJourney.path.join(" → ")}</span>{selectedJourney.finalPosition ? <b>{selectedJourney.finalPosition}.º</b> : null}</div> : null}
            <dl className={styles.tournamentKnockoutEvidence}><div><dt>Corrección</dt><dd>{knockout.authority.retiredMatches} retirado</dd></div><div><dt>Árbitro final</dt><dd>#{knockout.referees.final.refereeNumber}</dd></div><div><dt>Disciplina</dt><dd>Aplicada</dd></div><div><dt>Integridad</dt><dd>Canónica</dd></div></dl>
          </aside>
        </div>
        <section className={styles.tournamentBracketNotice}><strong>{tournament.nextPhase.message}</strong><span>Prórroga, penaltis, no-show y corrección trazados</span><code>{tournament.completionProof.qualificationChecksum.slice(0, 16)}</code></section>
      </> : null}
    </main>

    <section className={styles.tournamentNextPhase}>
      <span>Snapshot público · Torneo cerrado</span>
      <strong>{tournament.nextPhase.message}</strong>
      <small>GET-only · 0 escrituras remotas · R6C verificado.</small>
    </section>
  </div>;
}

const configurationSectionLabels: Record<string, string> = {
  discipline: "Disciplina",
  format: "Formato",
  incidents: "Incidencias",
  match: "Partidos",
  referees: "Árbitros",
  roster: "Plantillas",
  scoring: "Puntuación",
  visibility: "Visibilidad",
};

function DemoConfigurationView({ configuration }: { configuration: DemoWorldV2ConfigurationChunk }) {
  const future = [
    { active: configuration.futureCapabilities.automaticRoundRobin, label: "Round Robin automático" },
    { active: configuration.futureCapabilities.discipline, label: "Disciplina R5" },
    { active: configuration.futureCapabilities.refereeAssignments, label: "Asignación de árbitros" },
    { active: configuration.futureCapabilities.manualAssistedPairing, label: "Emparejamiento manual asistido" },
    { active: configuration.futureCapabilities.hybridPairing, label: "Emparejamiento híbrido" },
    { active: configuration.futureCapabilities.payments, label: "Pagos de competición" },
    { active: configuration.futureCapabilities.tournaments, label: "Tournament Engine" },
  ];
  return <div className={styles.configurationStack} data-demo-domain="configuration" data-demo-read-only="true">
    <section className={styles.configurationHero}>
      <div>
        <span className={styles.eyebrow}>Demo World V2.3 · GET-only</span>
        <h1>Centro de configuración</h1>
        <p>Dos RuleRevision reales de {configuration.competitionName}, congeladas por PostgreSQL y proyectadas sin datos privados.</p>
      </div>
      <div className={styles.configurationHealth}>
        <strong>{configuration.health.complete ? "Configuración coherente" : "Revisión necesaria"}</strong>
        <span>{configuration.health.errors} errores · {configuration.health.warnings} avisos</span>
        <small>v{configuration.currentEditionRevision} aplicada a la edición</small>
      </div>
    </section>

    <section className={styles.sectionBand}>
      <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Reglamento humano</span><h2>Estándar frente a personalizada</h2></div><span>Solo lectura</span></div>
      <div className={styles.configurationRevisionGrid}>
        {configuration.revisions.map((revision) => <article key={revision.revision}>
          <header><div><span>RuleRevision v{revision.revision}</span><h3>{revision.authoringMode === "SIMPLE" ? "Liga F7 estándar" : "Liga personalizada"}</h3></div><b>{revision.authoringMode === "SIMPLE" ? "Sencillo" : "Avanzado"}</b></header>
          <div className={styles.configurationMetrics}>
            <span><small>Partido</small><strong>{revision.matchDurationMinutes} min</strong></span>
            <span><small>Puntos</small><strong>{revision.pointsForWin} · {revision.pointsForDraw} · {revision.pointsForLoss}</strong></span>
            <span><small>No-show</small><strong>{revision.noShowWinnerScore} - {revision.noShowLoserScore}</strong></span>
            <span><small>Respuesta</small><strong>{revision.postponementResponseDeadlineHours} h</strong></span>
          </div>
          <div className={styles.configurationPolicy}>
            <div><small>Disciplina</small><strong>Amarilla cada {revision.yellowThreshold}</strong><p>{revision.cardCodes.map((code) => <span key={code} data-card={code}>{code}</span>)}</p></div>
            <div><small>Árbitro</small><strong>{revision.refereeUsage === "REQUIRED" ? "Obligatorio" : "Opcional"}</strong><p>{revision.feeMode === "FIXED" ? "Tarifa fija privada" : "Tarifa negociable"}</p></div>
          </div>
          <footer><span>{revision.healthComplete && revision.humanDocumentVerified ? "Health y documento verificados" : "Pendiente"}</span><code>{revision.checksum.slice(0, 12)}</code></footer>
        </article>)}
      </div>
    </section>

    <section className={styles.configurationCompare}>
      <div><span className={styles.eyebrow}>Comparador</span><h2>v{configuration.comparator.baseRevision} → v{configuration.comparator.targetRevision}</h2><p>La nueva revisión afecta solo a reglas futuras; no reescribe partidos, resultados ni sanciones anteriores.</p></div>
      <div>{configuration.comparator.changedSections.map((section) => <span key={section}>{configurationSectionLabels[section] ?? section}</span>)}</div>
    </section>

    <section className={styles.configurationBottom}>
      <div><span className={styles.eyebrow}>Consumo de motores</span><h2>Regla canónica activa</h2><dl><div><dt>Catálogo R5</dt><dd>{configuration.engineConsumption.r5CatalogCodes.join(" · ")}</dd></div><div><dt>Assignments</dt><dd>Árbitro obligatorio</dd></div><div><dt>Tarifa</dt><dd>Privada, sin importe público</dd></div><div><dt>Recibos RPC</dt><dd>{configuration.provenance.operationReceipts}</dd></div></dl></div>
      <div><span className={styles.eyebrow}>Capacidades</span><h2>Disponible y próximas fases</h2><ul>{future.map((item) => <li key={item.label} data-active={item.active}><span />{item.label}<b>{item.active ? "Activo" : "Próxima fase"}</b></li>)}</ul></div>
    </section>
  </div>;
}

function DemoClubView({ club, clubs, onClub }: {
  club: DemoWorldV2Club;
  clubs: DemoWorldV2Club[];
  onClub: (clubId: string) => void;
}) {
  return <div className={styles.demoProductView} data-demo-domain="club">
    <nav className={styles.entityRail} aria-label="Clubs del Mundo Demo">
      {clubs.map((entry) => <button aria-current={entry.id === club.id ? "page" : undefined} key={entry.id} onClick={() => onClub(entry.id)} type="button">{entry.name}</button>)}
    </nav>
    <PublicClubProfile club={club.publicProfile} embedded />
  </div>;
}

function demoRefereeProfile(referee: DemoWorldV2Referee, index: number): RefereeJson {
  return {
    areas: [{ generalArea: referee.municipality, municipality: referee.municipality }],
    availabilityStatus: referee.availabilityStatus,
    bio: referee.publicBio,
    clubs: referee.clubIds.map((clubId) => ({ id: clubId })),
    displayName: referee.displayName,
    experienceSinceYear: String(2012 + (index % 8)),
    marketplaceStatus: referee.marketplaceStatus,
    modalities: referee.modalities.map((modality) => ({ modality })),
    publicFee: referee.publicFee,
    slug: referee.slug,
    statistics: referee.statistics,
    verificationStatus: referee.verificationStatus,
  };
}

function DemoRefereesView({ assignments, referees }: { assignments: RefereeJson; referees: DemoWorldV2Referee[] }) {
  return <div className={styles.demoProductView} data-demo-domain="referees">
    <section className={styles.demoDomainHeading}>
      <div><span className={styles.eyebrow}>Mercado · perfiles públicos</span><h1>Árbitros disponibles</h1><p>Perfiles ficticios conectados a Clubs y a la Liga mediante asignaciones canónicas.</p></div>
      <span>{referees.length} perfiles</span>
    </section>
    <div className={styles.refereeGrid}>{referees.map((referee, index) => <RefereeProfileCard compact key={referee.id} profile={demoRefereeProfile(referee, index)} />)}</div>
    <RefereeAssignmentsClient embedded previewData={assignments} surface="my" />
  </div>;
}

type DemoPublicCompetitionPane = "directory" | "league" | "organizer" | "participant" | "request" | "tournament" | "unlisted" | "waitlist";

const demoPublicCompetitionPanes: Array<{ id: DemoPublicCompetitionPane; label: string }> = [
  { id: "directory", label: "Directorio" },
  { id: "league", label: "Liga pública" },
  { id: "tournament", label: "Torneo público" },
  { id: "request", label: "Solicitudes" },
  { id: "waitlist", label: "Lista de espera" },
  { id: "unlisted", label: "No listada" },
  { id: "organizer", label: "Organizador" },
  { id: "participant", label: "Participante" },
];

function DemoPublicCompetitionsView({ data }: { data: DemoWorldV2PublicCompetitionsChunk }) {
  const [pane, setPane] = useState<DemoPublicCompetitionPane>("directory");
  const requests = data.requests.map((request, index) => ({
    ...request,
    id: `demo-public-request-${index + 1}`,
    revision: request.status === "waitlisted" ? 2 : 1,
  }));
  const leagueCompetition = (data.league.hub.competition ?? {}) as Record<string, unknown>;
  const leagueCompetitionId = String(leagueCompetition.id ?? "demo-public-league");
  const requestFor = (status: DemoWorldV2PublicCompetitionsChunk["requests"][number]["status"]) => {
    const request = requests.find((entry) => entry.status === status);
    return request ? [{ ...request, competitionId: leagueCompetitionId }] : [];
  };
  const related = (view: DemoWorldV2PublicCompetitionsChunk["league"]) => ({
    bracket: (view.bracket ?? {}) as Record<string, unknown>,
    calendar: view.calendar,
    standings: view.standings,
  });
  const openFromDirectory = (slug: string) => {
    if (slug === data.tournament.slug) setPane("tournament");
    else setPane("league");
  };

  let content: ReactNode;
  if (pane === "directory") {
    content = <CompetitionDirectoryClient embedded initialData={data.directory} onOpen={openFromDirectory} />;
  } else if (pane === "tournament") {
    content = <PublicCompetitionHub embedded initialRelated={related(data.tournament)} initialSnapshot={data.tournament.hub} slug={data.tournament.slug} />;
  } else if (pane === "unlisted") {
    content = <PublicCompetitionHub embedded initialRelated={related(data.unlisted)} initialSnapshot={data.unlisted.hub} slug={data.unlisted.slug} />;
  } else if (pane === "organizer") {
    content = <PublicCompetitionHub embedded embeddedAuthenticated initialSnapshot={data.organizerPrivate.hub} slug={data.organizerPrivate.slug} />;
  } else if (pane === "request") {
    content = <PublicCompetitionHub embedded embeddedAuthenticated initialQueue={requests.map((request) => ({ ...request, competitionId: leagueCompetitionId }))} initialRelated={related(data.league)} initialSnapshot={data.league.hub} initialTab="registration" slug={data.league.slug} />;
  } else if (pane === "waitlist") {
    content = <PublicCompetitionHub embedded embeddedAuthenticated initialRelated={related(data.league)} initialRequests={requestFor("waitlisted")} initialSnapshot={data.league.hub} initialTab="registration" slug={data.league.slug} />;
  } else if (pane === "participant") {
    content = <PublicCompetitionHub embedded embeddedAuthenticated initialRelated={related(data.league)} initialRequests={requestFor("accepted")} initialSnapshot={data.league.hub} initialTab="registration" slug={data.league.slug} />;
  } else {
    content = <PublicCompetitionHub embedded initialRelated={related(data.league)} initialSnapshot={data.league.hub} slug={data.league.slug} />;
  }

  return <div className={styles.demoProductView} data-demo-domain="public-competitions" data-demo-read-only="true">
    <nav className={styles.publicCompetitionSubnav} aria-label="Escenarios de competiciones públicas">
      {demoPublicCompetitionPanes.map((entry) => <button aria-pressed={pane === entry.id} key={entry.id} type="button" onClick={() => setPane(entry.id)}>{entry.label}</button>)}
    </nav>
    <div key={pane}>{content}</div>
  </div>;
}

const organizerBillingScenarioLabels: Record<DemoWorldV2OrganizerBillingChunk["scenarios"][number]["id"], string> = {
  canceled_continuity: "Cancelado con continuidad",
  club_active: "Club activo",
  club_partner: "Club colaborador",
  past_due_grace: "Pago pendiente",
  team_active: "Equipo activo",
};

function DemoOrganizerBillingView({ billing }: { billing: DemoWorldV2OrganizerBillingChunk }) {
  const [scenarioId, setScenarioId] = useState<DemoWorldV2OrganizerBillingChunk["scenarios"][number]["id"]>("club_partner");
  const scenario = billing.scenarios.find(({ id }) => id === scenarioId) ?? billing.scenarios[0]!;
  return <div className={`${styles.demoProductView} ${styles.organizerBillingDemo}`} data-demo-domain="organizer-billing" data-demo-read-only="true">
    <section className={styles.demoDomainHeading}>
      <div><span className={styles.eyebrow}>ORGANIZER PLANS V1</span><h1>Planes y continuidad</h1><p>Estados canónicos de ejemplo sin cobros, datos personales ni escrituras remotas.</p></div>
      <span>Demo GET · Checkout live desactivado</span>
    </section>
    <nav className={styles.organizerBillingScenarioRail} aria-label="Escenarios ficticios de facturación">
      {billing.scenarios.map((entry) => <button aria-pressed={scenario.id === entry.id} key={entry.id} type="button" onClick={() => setScenarioId(entry.id)}>{organizerBillingScenarioLabels[entry.id]}</button>)}
    </nav>
    <section className={styles.organizerBillingScenario}>
      <header><span>{scenario.organizerKind === "CLUB" ? "Club" : "Equipo"}</span><h2>{scenario.organizerName}</h2><p>{scenario.note}</p></header>
      <div className={styles.organizerBillingStateGrid}>
        <span><small>Plan</small><strong>{scenario.planCode}</strong></span>
        <span><small>Cuenta</small><strong>{organizerBillingStatus(scenario.accountStatus)}</strong></span>
        <span><small>Acceso</small><strong>{organizerBillingStatus(scenario.accessStatus)}</strong></span>
        <span><small>Nuevas creaciones</small><strong>{scenario.creationAllowed ? "Permitidas" : "Bloqueadas"}</strong></span>
        {scenario.renewalAt ? <span><small>Renovación</small><strong>{organizerBillingDate(scenario.renewalAt)}</strong></span> : null}
        {scenario.graceEndsAt ? <span><small>Gracia hasta</small><strong>{organizerBillingDate(scenario.graceEndsAt)}</strong></span> : null}
        {scenario.continuityUntil ? <span><small>Continuidad hasta</small><strong>{organizerBillingDate(scenario.continuityUntil)}</strong></span> : null}
      </div>
    </section>
    <section className={styles.organizerBillingPlanGrid} aria-label="Catálogo ficticio de planes">
      {billing.catalog.plans.map((plan) => <article key={plan.planCode}>
        <header><span>{plan.organizerKind === "CLUB" ? "Club" : "Equipo"}</span><strong>{plan.displayName}</strong></header>
        <p>{plan.description}</p>
        {plan.planCode === "TEAM_ORGANIZER_PRO" ? <b>Add-on · conserva el plan base</b> : null}
        <ul>{plan.features.slice(0, 4).map((feature) => <li key={feature}>{organizerFeatureLabels[feature] ?? feature}</li>)}</ul>
        <footer><span>{organizerBillingStatus(plan.pricingStatus)}</span><small>{plan.features.length} capacidades · límites pendientes</small></footer>
      </article>)}
    </section>
  </div>;
}

export function DemoWorldApp({ manifest }: { manifest: DemoWorldV2Manifest }) {
  const [core, setCore] = useState<DemoWorldCoreChunk | null>(null);
  const [snapshot, setSnapshot] = useState<DemoWorldV2Snapshot | null>(null);
  const [loadingFullWorld, setLoadingFullWorld] = useState(false);
  const [session, setSession] = useState<DemoWorldSessionState>(() => readInitialDemoWorldSession(
    typeof window === "undefined" ? "" : window.location.search,
    typeof window === "undefined" ? undefined : window.sessionStorage,
  ));
  const [activeTab, setActiveTab] = useState<DemoWorldV2PrimaryTab>(() => demoWorldV2TabFromSearch(
    typeof window === "undefined" ? "" : window.location.search,
  ));
  const initialPerspectiveId = useRef(session.perspectiveId);
  const fullWorldRequest = useRef<Promise<DemoWorldV2Snapshot | null> | null>(null);
  const [selectedClubId, setSelectedClubId] = useState("demo_club_001");
  const [selectedLeagueMatchId, setSelectedLeagueMatchId] = useState<string | null>(null);
  const [selectedMatchId, setSelectedMatchId] = useState<string | null>(null);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [selectedTeamId, setSelectedTeamId] = useState<string | null>(null);
  const [openedBox, setOpenedBox] = useState<DemoWorldRewardBox | null>(null);
  const [RewardBoxComponent, setRewardBoxComponent] = useState<
    (typeof import("../reward-box-demo"))["RewardBoxDemo"] | null
  >(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  const openRewardBox = (box: DemoWorldRewardBox) => {
    setOpenedBox(box);
    if (RewardBoxComponent) return;
    void import("../reward-box-demo")
      .then((module) => setRewardBoxComponent(() => module.RewardBoxDemo))
      .catch(() => {
        setOpenedBox(null);
        setError("No se pudo cargar la animación de la caja.");
      });
  };

  useEffect(() => {
    document.body.classList.add("demo-world-active");
    return () => document.body.classList.remove("demo-world-active");
  }, []);

  useEffect(() => {
    let disposed = false;
    void loadDemoWorldV2Core(manifest)
      .then((loadedCore) => {
        if (disposed) return;
        const perspective = loadedCore.perspectives.find((entry) => entry.id === initialPerspectiveId.current) ?? loadedCore.perspectives[0]!;
        const teamId = perspective.teamId ?? loadedCore.teams[0]!.id;
        const teamMatches = loadedCore.preview.matches.filter((match) => match.homeTeamId === teamId || match.awayTeamId === teamId);
        const nextMatch = teamMatches.filter((match) => match.status === "scheduled").sort((left, right) => Date.parse(left.date) - Date.parse(right.date))[0] ?? teamMatches[0];
        setCore(loadedCore);
        setSelectedTeamId(teamId);
        setSelectedPlayerId(null);
        setSelectedMatchId(nextMatch?.id ?? null);
      })
      .catch((caught) => setError(caught instanceof Error ? caught.message : "No se pudo cargar el Mundo Demo."));
    return () => { disposed = true; };
  }, [manifest]);

  useEffect(() => {
    if (!core || snapshot || activeTab === "inicio" || fullWorldRequest.current) return;
    setLoadingFullWorld(true);
    const request = loadDemoWorldV2Snapshot(manifest, core)
      .then((world) => {
        setSnapshot(world);
        return world;
      })
      .catch((caught) => {
        setError(caught instanceof Error ? caught.message : "No se pudo cargar esta sección del Mundo Demo.");
        return null;
      })
      .finally(() => setLoadingFullWorld(false));
    fullWorldRequest.current = request;
  }, [activeTab, core, manifest, snapshot]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    writeDemoWorldSession(window.sessionStorage, session);
  }, [session]);

  useEffect(() => {
    if (!message) return;
    const timeout = window.setTimeout(() => setMessage(""), 3200);
    return () => window.clearTimeout(timeout);
  }, [message]);

  if (error) return <main className={styles.shell}><div className={styles.errorPanel}><strong>No se pudo abrir el Mundo Demo</strong><p>{error}</p><Link href="/">Volver</Link></div></main>;
  if (!core) return <LoadingWorld manifest={manifest} />;

  const world = snapshot ?? previewSnapshot(manifest, core);
  const perspective = world.core.perspectives.find((entry) => entry.id === session.perspectiveId) ?? world.core.perspectives[0]!;
  const baseCurrentPlayer = world.players.players.find((player) => player.id === perspective.playerId)!;
  const currentPlayer = playerWithDemoCosmetics(baseCurrentPlayer, session.equippedCosmeticKeys);
  const currentTeam = perspective.teamId ? world.core.teams.find((team) => team.id === perspective.teamId) ?? null : null;
  const selectedTeam = world.core.teams.find((team) => team.id === selectedTeamId) ?? currentTeam ?? world.core.teams[0]!;
  const teamMatches = world.matches.matches.filter((match) => currentTeam
    ? match.homeTeamId === currentTeam.id || match.awayTeamId === currentTeam.id
    : match.status === "scheduled" && match.publicOpenSlots > 0);
  const selectedMatch = world.matches.matches.find((match) => match.id === selectedMatchId) ?? teamMatches[0] ?? null;
  const selectedPlayerSource = world.players.players.find((player) => player.id === selectedPlayerId) ?? null;
  const selectedPlayer = selectedPlayerSource?.id === currentPlayer.id
    ? currentPlayer
    : selectedPlayerSource;
  const selectedClub = snapshot?.clubsReferees.clubs.find((club) => club.id === selectedClubId)
    ?? snapshot?.clubsReferees.clubs[0]
    ?? null;
  const selectedLeagueMatchPreview = selectedLeagueMatchId
    ? snapshot?.competitions.matchPreviews[selectedLeagueMatchId] ?? null
    : null;
  const selectedLeagueMatchDisciplinePreview = selectedLeagueMatchId
    ? snapshot?.competitions.matchDisciplinePreviews[selectedLeagueMatchId] ?? null
    : null;
  const selectedLeagueMatchRefereePreview = selectedLeagueMatchId
    ? snapshot?.competitions.refereeAssignmentPreviews[selectedLeagueMatchId] ?? null
    : null;
  const notifications = world.activity.notifications;

  function updateSession(next: (current: DemoWorldSessionState) => DemoWorldSessionState) {
    setSession((current) => next(current));
  }

  function navigate(tab: DemoWorldV2PrimaryTab, preserveLeagueMatch = false) {
    if (!preserveLeagueMatch) setSelectedLeagueMatchId(null);
    setActiveTab(tab);
    const params = new URLSearchParams(window.location.search);
    params.set("tab", tab);
    params.set("perspective", session.perspectiveId);
    window.history.replaceState(null, "", `/demo?${params.toString()}`);
    window.scrollTo({ behavior: "smooth", top: 0 });
  }

  function equipCosmetic(cosmeticKey: string) {
    const item = PLAYER_COSMETIC_CATALOG.find((entry) => entry.key === cosmeticKey);
    if (!item) return;
    updateSession((current) => ({
      ...current,
      equippedCosmeticKeys: [
        ...current.equippedCosmeticKeys.filter((key) => PLAYER_COSMETIC_CATALOG.find((entry) => entry.key === key)?.slot !== item.slot),
        item.key,
      ],
      inventoryCosmeticKeys: [...new Set([...current.inventoryCosmeticKeys, item.key])],
      newCosmeticKeys: current.newCosmeticKeys.filter((key) => key !== item.key),
    }));
    setMessage(`${item.name} equipado en tu ficha demo.`);
  }

  function choosePerspective(perspectiveId: DemoWorldPerspective["id"]) {
    const nextPerspective = world.core.perspectives.find((entry) => entry.id === perspectiveId)!;
    const nextTeamId = nextPerspective.teamId ?? world.core.teams[0]!.id;
    const nextMatches = world.matches.matches.filter((match) => match.homeTeamId === nextTeamId || match.awayTeamId === nextTeamId);
    const nextMatch = nextMatches.filter((match) => match.status === "scheduled").sort((left, right) => Date.parse(left.date) - Date.parse(right.date))[0] ?? nextMatches[0];
    updateSession((current) => ({ ...current, perspectiveId }));
    setSelectedPlayerId(null);
    setSelectedTeamId(nextTeamId);
    setSelectedMatchId(nextMatch?.id ?? null);
    const params = new URLSearchParams(window.location.search);
    params.set("perspective", perspectiveId);
    params.set("tab", activeTab);
    window.history.replaceState(null, "", `/demo?${params.toString()}`);
  }

  function openMatch(matchId: string) {
    setSelectedMatchId(matchId);
    navigate("partido");
  }

  function openLeagueMatch(matchId: string) {
    setSelectedLeagueMatchId(matchId);
    navigate("partido", true);
  }

  function openClub(clubId: string) {
    setSelectedClubId(clubId);
    navigate("club");
  }

  function openTeam(teamId: string) {
    setSelectedTeamId(teamId);
    navigate("equipo");
  }

  function resetWorld() {
    const reset = resetDemoWorldSession(window.sessionStorage);
    setSession(reset);
    setActiveTab("inicio");
    setSelectedPlayerId(null);
    setSelectedLeagueMatchId(null);
    setSelectedClubId("demo_club_001");
    setSelectedTeamId("demo_team_001");
    const nextMatch = world.matches.matches.filter((match) => match.homeTeamId === "demo_team_001" && match.status === "scheduled").sort((left, right) => Date.parse(left.date) - Date.parse(right.date))[0];
    setSelectedMatchId(nextMatch?.id ?? null);
    window.history.replaceState(null, "", "/demo");
    setMessage("Mundo Demo restaurado al snapshot original.");
  }

  return (
    <main className={styles.shell} data-demo-world="ready" data-demo-perspective={perspective.id} data-demo-tab={activeTab}>
      <DemoHeader activeTab={activeTab} manifest={manifest} onReset={resetWorld} onTab={navigate} perspective={perspective} perspectives={world.core.perspectives} setPerspective={choosePerspective} />
      <div className={styles.content}>
        {activeTab === "inicio" ? <WorldHome currentPlayer={currentPlayer} currentTeam={currentTeam} notifications={notifications} onMatch={openMatch} onPlayer={setSelectedPlayerId} onTab={navigate} perspective={perspective} snapshot={world} teamMatches={teamMatches} /> : null}
        {activeTab !== "inicio" && !snapshot ? <div className={styles.secondaryLoading} role="status"><span className={styles.loadingMark}>IQ</span><strong>{loadingFullWorld ? "Cargando esta sección" : "Preparando datos"}</strong><p>Solo descargamos el dominio que acabas de abrir.</p></div> : null}
        {snapshot && activeTab === "partido" && selectedLeagueMatchPreview ? <div className={styles.demoProductView} data-demo-domain="league-match"><LeagueMatchOperationsClient disciplinePreviewData={selectedLeagueMatchDisciplinePreview} embedded previewData={selectedLeagueMatchPreview} refereeAssignmentPreviewData={selectedLeagueMatchRefereePreview} surface="match" /></div> : null}
        {snapshot && activeTab === "partido" && !selectedLeagueMatchPreview ? <MatchView currentPlayer={currentPlayer} currentTeam={currentTeam} key={perspective.id} match={selectedMatch} onLocalAttendance={(status) => { if (!selectedMatch) return; updateSession((current) => ({ ...current, attendanceByMatch: { ...current.attendanceByMatch, [selectedMatch.id]: status } })); setMessage(`Asistencia ${status === "voy" ? "confirmada" : status === "duda" ? "en duda" : "cancelada"} solo en esta sesión demo.`); }} onMatch={openMatch} onPlayer={setSelectedPlayerId} perspective={perspective} session={session} setMessage={setMessage} snapshot={snapshot} teamMatches={teamMatches} /> : null}
        {snapshot && activeTab === "mercado" ? <MarketView currentPlayer={currentPlayer} onMatch={openMatch} onPlayer={setSelectedPlayerId} onTeam={openTeam} perspective={perspective} setMessage={setMessage} snapshot={snapshot} /> : null}
        {snapshot && activeTab === "equipo" ? <TeamView currentTeam={currentTeam} onPlayer={setSelectedPlayerId} onTeam={setSelectedTeamId} selectedTeam={selectedTeam} snapshot={snapshot} /> : null}
        {snapshot && activeTab === "perfil" ? <ProfileView currentPlayer={currentPlayer} currentTeam={currentTeam} notifications={notifications} onEquipCosmetic={equipCosmetic} onOpenBox={openRewardBox} onPerspective={choosePerspective} onPlayer={setSelectedPlayerId} onRead={(notificationId) => updateSession((current) => ({ ...current, readNotificationIds: [...new Set([...current.readNotificationIds, notificationId])] }))} perspective={perspective} perspectives={world.core.perspectives} session={session} snapshot={snapshot} /> : null}
        {snapshot && activeTab === "liga" ? <LeagueOverviewView onClub={openClub} onMatch={openLeagueMatch} onTab={navigate} snapshot={snapshot} /> : null}
        {snapshot && activeTab === "torneo" ? <DemoTournamentView tournament={snapshot.tournament} /> : null}
        {snapshot && activeTab === "competiciones" ? <DemoPublicCompetitionsView data={snapshot.publicCompetitions} /> : null}
        {snapshot && activeTab === "configuracion" ? <DemoConfigurationView configuration={snapshot.configuration} /> : null}
        {snapshot && activeTab === "clasificacion" ? <div className={styles.demoProductView} data-demo-domain="standings"><LeagueMatchOperationsClient embedded previewData={snapshot.competitions.standingsPreview} surface="standings" /></div> : null}
        {snapshot && activeTab === "jornadas" ? <div className={styles.demoProductView} data-demo-domain="rounds"><LeagueSchedulingClient embedded onOpenMatch={(canonicalMatchId) => {
          const match = snapshot.competitions.matches.find((entry) => entry.canonicalMatchId === canonicalMatchId);
          if (match) openLeagueMatch(match.id);
        }} previewData={snapshot.competitions.schedulePreview} surface="public" /></div> : null}
        {snapshot && activeTab === "disciplina" ? <div className={styles.demoProductView} data-demo-domain="discipline"><CompetitionDisciplineClient competitionId={snapshot.competitions.competition.id} embedded previewData={snapshot.competitions.disciplinePreview} surface="public" /></div> : null}
        {snapshot && activeTab === "club" && selectedClub ? <DemoClubView club={selectedClub} clubs={snapshot.clubsReferees.clubs} onClub={setSelectedClubId} /> : null}
        {snapshot && activeTab === "arbitros" ? <DemoRefereesView assignments={snapshot.clubsReferees.refereeAssignmentPreview} referees={snapshot.clubsReferees.referees} /> : null}
        {snapshot && activeTab === "planes" ? <DemoOrganizerBillingView billing={snapshot.organizerBilling} /> : null}
      </div>
      <MobileAppNav active={activeTab as MobileAppTab} onNavigate={(tab) => navigate(tab as DemoWorldV2PrimaryTab)} />
      {selectedPlayer ? <PlayerModal onClose={() => setSelectedPlayerId(null)} player={selectedPlayer} /> : null}
      {openedBox && RewardBoxComponent ? <RewardBoxComponent
        actionLabel="Guardar en esta demo"
        description={`Recompensa local: ${openedBox.rewardCosmeticKey}`}
        eyebrow="Caja de logro · Mundo Demo"
        onAction={() => {
          updateSession((current) => ({
            ...current,
            inventoryCosmeticKeys: [...new Set([...current.inventoryCosmeticKeys, openedBox.rewardCosmeticKey])],
            newCosmeticKeys: [...new Set([...current.newCosmeticKeys, openedBox.rewardCosmeticKey])],
            openedBoxIds: [...new Set([...current.openedBoxIds, openedBox.id])],
          }));
          setOpenedBox(null);
          setMessage("Pieza nueva guardada en la sesión demo. Ya puedes equiparla.");
        }}
        onClose={() => setOpenedBox(null)}
        open
        title="Recompensa descubierta"
      /> : null}
      {message ? <div className={styles.toast} role="status">{message}</div> : null}
    </main>
  );
}
