"use client";

import { useMemo, useState } from "react";
import {
  isTerritoryReadinessState,
  readinessPublicSurface,
  type ProvincialFeatureFlags,
  type TerritoryReadinessSnapshot,
} from "../../simulation/season-ranking-lab/src/territory-award-readiness";
import styles from "./ranking-provincial.module.css";

export type ProvincialPilotTerritory = {
  provinceCode: string;
  provinceName: string;
  ranking: Array<{
    displayName: string;
    logicalOpponents: number;
    movement: number;
    playerId: string;
    rank: number;
    score: number;
    validChallenges: number;
  }>;
  snapshot: TerritoryReadinessSnapshot;
  unranked: Array<{
    displayName: string;
    missingChallenges: number;
    missingLogicalOpponents: number;
    playerId: string;
  }>;
};

const stateLabels = {
  ranking_active: "Clasificación en desarrollo",
  ranking_inactive: "Clasificación aún no disponible",
  trophy_not_ready: "Ranking activo · premios en desarrollo",
  trophy_ready: "Territorio preparado",
} as const;

function movementLabel(movement: number) {
  if (movement > 0) return `↑ ${movement}`;
  if (movement < 0) return `↓ ${Math.abs(movement)}`;
  return "=";
}

function PlayerStatus({ territory }: { territory: ProvincialPilotTerritory }) {
  const choices = [
    ...territory.ranking.slice(0, 8).map((player) => ({ id: player.playerId, label: player.displayName, type: "ranked" as const })),
    ...territory.unranked.slice(0, 5).map((player) => ({ id: player.playerId, label: player.displayName, type: "unranked" as const })),
  ];
  const [playerId, setPlayerId] = useState(choices[0]?.id ?? "");
  const ranked = territory.ranking.find((player) => player.playerId === playerId);
  const unranked = territory.unranked.find((player) => player.playerId === playerId);

  return (
    <section className={styles.playerPanel}>
      <header>
        <div>
          <span>Mi situación</span>
          <h2>Acceso al ranking</h2>
        </div>
        <label>
          <span>Jugador de prueba</span>
          <select value={playerId} onChange={(event) => setPlayerId(event.target.value)}>
            {choices.map((choice) => <option value={choice.id} key={choice.id}>{choice.label}</option>)}
          </select>
        </label>
      </header>
      {ranked ? (
        <div className={styles.playerRanked}>
          <strong>#{ranked.rank} {territory.provinceName}</strong>
          <span>Season Score {ranked.score.toFixed(1)}</span>
          <small>{ranked.validChallenges} Retos válidos · {ranked.logicalOpponents} rivales</small>
        </div>
      ) : unranked ? (
        <div className={styles.playerMissing}>
          <strong>Aún no apareces en la clasificación</strong>
          <span>Te faltan:</span>
          <div>
            <b>{unranked.missingChallenges} Retos válidos</b>
            <b>{unranked.missingLogicalOpponents} rivales diferentes</b>
          </div>
        </div>
      ) : <p>Este territorio todavía no tiene jugadores de prueba.</p>}
    </section>
  );
}

export function ProvincialRankingPilot({ featureFlags, territories }: { featureFlags: ProvincialFeatureFlags; territories: ProvincialPilotTerritory[] }) {
  const defaultCode = territories.find(({ provinceCode }) => provinceCode === "08")?.provinceCode
    ?? territories[0]?.provinceCode
    ?? "";
  const [provinceCode, setProvinceCode] = useState(defaultCode);
  const territory = useMemo(() => (
    territories.find((item) => item.provinceCode === provinceCode)
      ?? territories[0]
  ), [provinceCode, territories]);

  if (!territory) return <main className={styles.empty}>Sin territorios de laboratorio.</main>;
  const readinessState = isTerritoryReadinessState(territory.snapshot.readinessState)
    ? territory.snapshot.readinessState
    : "ranking_inactive";
  const publicSurface = readinessPublicSurface(
    territory.snapshot,
    featureFlags,
  );

  return (
    <main className={styles.shell}>
      <header className={styles.hero}>
        <div>
          <span>Pachangas IQ · piloto provincial</span>
          <h1>Top {territory.provinceName}</h1>
          <p>Temporada {territory.snapshot.season.replace("-", "/")}</p>
        </div>
        <label>
          <span>Provincia</span>
          <select value={territory.provinceCode} onChange={(event) => setProvinceCode(event.target.value)}>
            {territories.map((item) => <option value={item.provinceCode} key={item.provinceCode}>{item.provinceName}</option>)}
          </select>
        </label>
      </header>

      <section className={styles.readinessBand} data-state={readinessState}>
        <div>
          <span>Estado territorial</span>
          <strong>{stateLabels[readinessState]}</strong>
        </div>
        <p>{publicSurface.message}</p>
        <small>Revisión {territory.snapshot.revision} · calculado {new Date(territory.snapshot.calculatedAt).toLocaleDateString("es-ES")}</small>
      </section>

      <div className={styles.layout}>
        <section className={styles.rankingPanel}>
          <header>
            <div>
              <span>Posición en directo</span>
              <h2>Season Score</h2>
            </div>
            <b>55 · 30 · 15</b>
          </header>
          {publicSurface.rankingVisible ? (
            <ol className={styles.rankingList}>
              {territory.ranking.slice(0, 30).map((player) => (
                <li key={player.playerId}>
                  <b>{player.rank}</b>
                  <span>{player.displayName}<small>{player.validChallenges} Retos · {player.logicalOpponents} rivales</small></span>
                  <strong>{player.score.toFixed(1)}</strong>
                  <i data-direction={player.movement === 0 ? "same" : player.movement > 0 ? "up" : "down"}>{movementLabel(player.movement)}</i>
                </li>
              ))}
            </ol>
          ) : <div className={styles.notVisible}><strong>La clasificación todavía no se publica.</strong><span>Volverá a evaluarse en la siguiente ventana territorial.</span></div>}
        </section>

        <aside className={styles.sideColumn}>
          <PlayerStatus key={territory.provinceCode} territory={territory} />
          <section className={styles.signalPanel}>
            <span>Actividad de la zona</span>
            <h2>Estado agregado</h2>
            <dl>
              <div><dt>Equipos activos</dt><dd>{territory.snapshot.signals.activeTeams}</dd></div>
              <div><dt>Jugadores rankeados</dt><dd>{territory.snapshot.signals.rankingEligiblePlayers}</dd></div>
              <div><dt>Candidatos 25/10</dt><dd>{territory.snapshot.signals.awardCandidatePlayers}</dd></div>
              <div><dt>Historia observada</dt><dd>{territory.snapshot.signals.observedHistoryWeeks} sem.</dd></div>
            </dl>
            <p>Estas métricas describen madurez del territorio. La revisión individual se realiza por separado al cerrar la temporada.</p>
          </section>
        </aside>
      </div>

      <footer className={styles.footer}>
        <span>Rankings provinciales: {featureFlags.provincialRankingsEnabled ? "activos" : "desactivados"}</span>
        <strong>Premios provinciales: {featureFlags.provincialAwardsEnabled ? "activos" : "desactivados"}</strong>
      </footer>
    </main>
  );
}
