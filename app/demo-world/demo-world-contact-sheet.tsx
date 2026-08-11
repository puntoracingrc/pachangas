import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import { TeamShieldView } from "../_components/team-shield-view";
import { TEAM_SHIELD_RENDER_CATALOG } from "../team-shield-cosmetics-catalog";
import coreJson from "../../public/demo-world/v1/core.json";
import playersJson from "../../public/demo-world/v1/players.json";
import { demoAvatarDataUri } from "./demo-world-client-state";
import type { DemoWorldCoreChunk, DemoWorldPlayer, DemoWorldPlayersChunk } from "./demo-world-contract";
import styles from "./demo-world-contact-sheet.module.css";

const core = coreJson as unknown as DemoWorldCoreChunk;
const players = playersJson as unknown as DemoWorldPlayersChunk;

const facetLabels = {
  defending: "DEF",
  dribbling: "REG",
  pace: "RIT",
  passing: "PAS",
  physical: "FIS",
  shooting: "TIR",
} as const;

function ratingScore(player: DemoWorldPlayer) {
  return player.rating.currentOverall === null ? "POR" : Math.round(player.rating.currentOverall);
}

function DemoPlayerCard({ player }: { player: DemoWorldPlayer }) {
  return (
    <PlayerCosmeticCard
      ariaLabel={`Ficha de ${player.name}`}
      facets={Object.entries(player.rating.currentFacets).map(([key, value]) => ({
        key,
        label: facetLabels[key as keyof typeof facetLabels],
        value: Math.round(value),
      }))}
      loadout={player.cosmetics}
      meta={`${player.appearances} PJ · ${player.goals} G`}
      name={player.name}
      photoAlt={`Avatar ficticio de ${player.name}`}
      photoSrc={demoAvatarDataUri(player.name, player.avatarHue)}
      position={player.position.abbreviation}
      score={ratingScore(player)}
    />
  );
}

export function DemoWorldContactSheet({ kind }: { kind: "players" | "teams" }) {
  const representativePlayers = players.players.filter((_, index) => index % 8 === 0).slice(0, 42);

  return (
    <main className={styles.sheet} data-contact-sheet={kind}>
      <header>
        <span>Demo World V1 · QA visual</span>
        <h1>{kind === "teams" ? "Equipos y escudos" : "Jugadores y cartas"}</h1>
        <p>
          {kind === "teams"
            ? `${core.teams.length} combinaciones renderizadas con TeamShieldView.`
            : `${representativePlayers.length} muestras de ${players.players.length} jugadores renderizadas con PlayerCosmeticCard.`}
        </p>
      </header>

      {kind === "teams" ? (
        <section className={styles.teamGrid} aria-label="Hoja de equipos y escudos">
          {core.teams.map((team) => (
            <article className={styles.teamItem} key={team.id}>
              <TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={team.shield} label={`Escudo de ${team.name}`} size={82} />
              <div>
                <strong>{team.name}</strong>
                <span>{team.publicLocation}</span>
                <small>{team.stats.matchesPlayed} PJ · {team.stats.challengeWins} victorias en Retos</small>
              </div>
            </article>
          ))}
        </section>
      ) : (
        <section className={styles.playerGrid} aria-label="Hoja de jugadores y cartas">
          {representativePlayers.map((player) => (
            <article className={styles.playerItem} key={player.id}>
              <DemoPlayerCard player={player} />
              <span>{core.teams.find(({ id }) => id === player.teamId)?.name ?? "Agente libre"}</span>
            </article>
          ))}
        </section>
      )}
    </main>
  );
}
