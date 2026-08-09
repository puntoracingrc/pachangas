import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import configData from "../../season-ranking-lab/season_score_config.json";
import {
  candidatesFromDataset,
  createNetworkEcosystem,
  type EcosystemScenario,
} from "../../season-ranking-lab/src/network-diversity-v31";
import { networkDatasetReadinessSignals } from "../../season-ranking-lab/src/territory-readiness-simulation";
import {
  PROVINCIAL_PILOT_FLAGS,
  PROVINCIAL_FEATURE_FLAG_KEYS,
  PROVINCIAL_READINESS_POLICY,
  PROVINCIAL_SEASON_CLOSE_PHASES,
  RANKING_SCOPE_RELEASE,
  closeProvincialSeason,
  createTerritoryReadinessSnapshot,
  readinessPublicSurface,
  territoryReadinessTelemetry,
  type TerritoryReadinessSignals,
  type TerritoryReadinessSnapshot,
} from "../../season-ranking-lab/src/territory-award-readiness";
import { TERRITORY_BY_PROVINCE } from "../../season-ranking-lab/src/territories";
import { v3Baseline } from "../../season-ranking-lab/src/v3-validation";
import type { SeasonScoreConfig } from "../../season-ranking-lab/src/types";
import { loadSyntheticLocalEnv } from "../src/local-env";
import { SyntheticWorldStore } from "../src/store";
import { buildSyntheticTerritoryReadiness } from "../src/territory-readiness";

const SOURCE_WORLD_ID = "3df9494d-3b8c-4447-96e8-d5244892af78";
const SOURCE_REVISION = 313;
const SOURCE_SEQUENCE = 69_458;
const ROOT = resolve(new URL("../../..", import.meta.url).pathname);
const GENERATED = resolve(ROOT, "simulation/synthetic-world/generated");
const EXPORTS = resolve(ROOT, "simulation/synthetic-world/exports");
const TEAM_COUNTS = [10, 20, 30, 50, 75, 100, 150] as const;

function hash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function isoWindow(index: number) {
  return new Date(Date.UTC(2027, 0, 1 + index * 28, 12)).toISOString();
}

function growthScenario(config: SeasonScoreConfig, scenario: EcosystemScenario, seed: number) {
  const history: TerritoryReadinessSnapshot[] = [];
  return TEAM_COUNTS.map((teamCount, index) => {
    const dataset = createNetworkEcosystem({ scenario, seed: seed + teamCount, teamCount });
    const candidates = candidatesFromDataset(dataset, config);
    const signals = networkDatasetReadinessSignals({ candidates, dataset });
    const snapshot = createTerritoryReadinessSnapshot({
      calculatedAt: isoWindow(index),
      history,
      season: "2026-27",
      signals,
      territory: "08",
    });
    history.push(snapshot);
    return { snapshot, teamCount };
  });
}

function temporalHistory() {
  const history: TerritoryReadinessSnapshot[] = [];
  const inactive: TerritoryReadinessSignals = { activePlayers: 24, activeTeams: 3, awardCandidatePlayers: 0, independentOpponentEdges: 2, independentTeamCoverage: 0.67, logicalOpponentEdges: 3, medianChallenges: 2, medianCompetitiveConfidence: 0.81, medianLogicalOpponents: 2, observedHistoryWeeks: 2, rankingEligiblePlayers: 0, validChallenges: 12 };
  const active: TerritoryReadinessSignals = { activePlayers: 54, activeTeams: 6, awardCandidatePlayers: 0, independentOpponentEdges: 8, independentTeamCoverage: 1, logicalOpponentEdges: 9, medianChallenges: 16, medianCompetitiveConfidence: 0.82, medianLogicalOpponents: 6, observedHistoryWeeks: 7, rankingEligiblePlayers: 7, validChallenges: 90 };
  const notReady: TerritoryReadinessSignals = { activePlayers: 82, activeTeams: 10, awardCandidatePlayers: 0, independentOpponentEdges: 18, independentTeamCoverage: 1, logicalOpponentEdges: 22, medianChallenges: 20, medianCompetitiveConfidence: 0.83, medianLogicalOpponents: 8, observedHistoryWeeks: 12, rankingEligiblePlayers: 12, validChallenges: 180 };
  const ready: TerritoryReadinessSignals = { activePlayers: 151, activeTeams: 21, awardCandidatePlayers: 15, independentOpponentEdges: 53, independentTeamCoverage: 1, logicalOpponentEdges: 57, medianChallenges: 30, medianCompetitiveConfidence: 0.85, medianLogicalOpponents: 13, observedHistoryWeeks: 30, rankingEligiblePlayers: 34, validChallenges: 448 };
  const windows = [inactive, active, active, notReady, notReady, ready, ready, ready];
  return windows.map((signals, index) => {
    const snapshot = createTerritoryReadinessSnapshot({
      calculatedAt: isoWindow(index),
      history,
      season: "2026-27",
      signals,
      territory: "08",
    });
    history.push(snapshot);
    return snapshot;
  });
}

function markdownTable(headers: string[], rows: Array<Array<number | string>>) {
  return `| ${headers.join(" | ")} |\n| ${headers.map(() => "---").join(" | ")} |\n${rows.map((row) => `| ${row.join(" | ")} |`).join("\n")}`;
}

function report(result: Awaited<ReturnType<typeof run>>) {
  const growthRows = result.growth.healthy.map(({ snapshot, teamCount }) => [
    teamCount,
    snapshot.signals.rankingEligiblePlayers,
    snapshot.signals.awardCandidatePlayers,
    snapshot.signals.validChallenges,
    snapshot.signals.independentOpponentEdges,
    snapshot.observedState,
    snapshot.readinessState,
  ]);
  const sourceRows = result.sourceTerritories.map(({ provinceCode, provinceName, snapshot }) => [
    provinceCode,
    provinceName,
    snapshot.signals.activeTeams,
    snapshot.signals.rankingEligiblePlayers,
    snapshot.signals.awardCandidatePlayers,
    snapshot.readinessState,
  ]);
  return `# TOPS V1 - Territory Award Readiness y piloto provincial

## Decisión

Season Score queda congelado en **55% Calidad, 30% Competición y 15% Oposición**, con ventana \`recent_30\`. La elegibilidad de ranking permanece en 15 evidencias, 6 rivales lógicos, fiabilidad >= 0,45 y actividad <= 12 semanas. El baseline individual de premio permanece en 25 Retos, 10 rivales, confianza >= 0,72, fiabilidad >= 0,55 y actividad reciente.

\`territory_award_readiness\` no modifica puntos ni aplica multiplicadores territoriales. Responde una pregunta distinta de la certificación individual: si el ecosistema provincial ofrece evidencia suficiente para habilitar premios.

## Estados

- \`ranking_inactive\`: no alcanza el mínimo para mostrar una tabla significativa.
- \`ranking_active\`: la clasificación puede mostrarse, pero todavía no existe una población Top 10 completa.
- \`trophy_not_ready\`: hay Top 10 visible, pero el territorio no puede certificar premios.
- \`trophy_ready\`: la madurez territorial permite pasar después a la decisión individual de integridad.

## Señales y razones

El snapshot conserva equipos y jugadores activos, población rankeada, candidatos 25/10 sin usar la decisión antifraude individual, Retos válidos, aristas técnicas, aristas lógicas independientes, cobertura de equipos conectados, medianas de Retos/rivales/confianza e historia observada. Los códigos públicos son: \`insufficient_active_teams\`, \`insufficient_ranking_population\`, \`insufficient_award_candidates\`, \`insufficient_independent_competition\`, \`insufficient_valid_challenges\`, \`insufficient_history\` y \`ready\`.

No se expone en la UI pública ningún motivo antifraude. La telemetría agregada no contiene nombres, correos, IDs de usuario ni coordenadas.

## Hysteresis e historial

Cada snapshot tiene \`calculatedAt\`, revisión monotónica, estado observado, estado confirmado, razones y señales. \`trophy_ready\` exige tres ventanas consecutivas; las demás promociones, dos. Una degradación exige tres ventanas bajas. Los premios históricos ya concedidos no se eliminan. En el cierre se congela el ranking, se fija readiness, se reconcilia integridad y solo después se certifican reconocimientos.

## Flags y scopes

- \`provincial_rankings_enabled=true\`.
- \`provincial_awards_enabled=false\` en el piloto.
- Comunidad autónoma: LAB ONLY.
- España: LAB ONLY.
- Rankings ON / awards OFF es un estado soportado y probado.

## Crecimiento territorial sano

${markdownTable(["Equipos", "Ranking", "Candidatos 25/10", "Retos", "Aristas independientes", "Observado", "Confirmado"], growthRows)}

Con 10 equipos el ranking puede existir, pero el territorio queda \`trophy_not_ready\`: solo hay nueve rivales posibles y no se rebaja 25/10. La red sana alcanza \`trophy_ready\` después de tres ventanas maduras; no queda bloqueada por el \`externalNetworkRatio\` absoluto.

## Red manipulada

El escenario manipulado puede alcanzar madurez territorial cuando tiene volumen y conexiones observables. Eso no certifica a sus jugadores: cada candidato sigue pasando después por V3 e integridad individual. \`TERRITORY READY?\` y \`PLAYER TRUSTWORTHY?\` permanecen separados.

## Synthetic World original

- Mundo: \`${result.source.worldId}\`.
- Revisión: ${result.source.revision}.
- Secuencia: ${result.source.eventSequence}.
- SHA-256 antes/después: \`${result.source.hashBefore}\` / \`${result.source.hashAfter}\`.

${markdownTable(["Código", "Provincia", "Equipos", "Ranking", "Candidatos", "Readiness"], sourceRows)}

El mundo original no se guarda ni se modifica; TOPS V1 solo genera read models y telemetría agregada.

## Cierre y política #11

Fases: ${PROVINCIAL_SEASON_CLOSE_PHASES.map((phase) => `\`${phase}\``).join(" -> ")}. Si el territorio no está preparado, la clasificación se archiva sin trofeo. Si está preparado y awards está activo, un jugador limpio puede recibir premio y uno pendiente conserva su trofeo pendiente. El #11 nunca asciende automáticamente por un #8 pendiente.

## Producto

La UI piloto provincial muestra posición viva, Season Score, movimiento, Retos válidos y rivales. Un no elegible solo ve cuántos Retos y rivales le faltan. \`live_position\` no equivale a \`season_award\`. M3 permanece \`experimental_reference\`; V3, Rating V2, GRL, facetas y assessments no cambian.
`;
}

async function run() {
  loadSyntheticLocalEnv();
  const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
  const config = v3Baseline(previous);
  const healthyGrowth = growthScenario(config, "healthy", 20261700);
  const manipulatedGrowth = growthScenario(config, "manipulated", 20261800);
  const timeHistory = temporalHistory();

  const store = new SyntheticWorldStore();
  const source = await store.loadWorld(SOURCE_WORLD_ID);
  if (source.revision !== SOURCE_REVISION || source.state.eventSequence !== SOURCE_SEQUENCE) {
    throw new Error(`SOURCE_WORLD_CHANGED expected r${SOURCE_REVISION}/seq${SOURCE_SEQUENCE}, actual r${source.revision}/seq${source.state.eventSequence}`);
  }
  const hashBefore = hash(source.state);
  const sourceTerritories = buildSyntheticTerritoryReadiness(source).map((territory) => ({
    ...territory,
    provinceName: TERRITORY_BY_PROVINCE.get(territory.provinceCode)?.provinceName ?? `Provincia ${territory.provinceCode}`,
    publicSurface: readinessPublicSurface(territory.snapshot, PROVINCIAL_PILOT_FLAGS),
  }));
  const hashAfter = hash(source.state);
  if (hashBefore !== hashAfter) throw new Error("SOURCE_WORLD_MUTATED_IN_MEMORY");

  const finalReadiness = healthyGrowth.at(-1)!.snapshot;
  const seasonClose = closeProvincialSeason({
    candidates: [
      { individualDecision: "clean", playerId: "rank-1-clean", rank: 1 },
      { individualDecision: "pending_integrity_review", playerId: "rank-8-pending", rank: 8 },
      { individualDecision: "clean", playerId: "rank-11-clean", rank: 11 },
    ],
    flags: { provincialAwardsEnabled: true, provincialRankingsEnabled: true },
    readiness: finalReadiness,
  });
  const result = {
    contract: {
      awardBaseline: { competitiveConfidence: 0.72, logicalOpponents: 10, ratingReliability: 0.55, recentActivityWeeks: 12, validChallenges: 25 },
      formula: { competition: 30, opposition: 15, quality: 55, window: "recent_30" },
      individualIntegritySeparate: true,
      policy: PROVINCIAL_READINESS_POLICY,
      rankingEligibility: { logicalOpponents: 6, ratingReliability: 0.45, recentActivityWeeks: 12, validChallenges: 15 },
      territoryMultipliers: false,
    },
    featureFlags: PROVINCIAL_PILOT_FLAGS,
    featureFlagKeys: PROVINCIAL_FEATURE_FLAG_KEYS,
    growth: { healthy: healthyGrowth, manipulated: manipulatedGrowth },
    m3: "experimental_reference",
    scopes: RANKING_SCOPE_RELEASE,
    seasonClose,
    seasonClosePhases: PROVINCIAL_SEASON_CLOSE_PHASES,
    source: { eventSequence: source.state.eventSequence, hashAfter, hashBefore, revision: source.revision, worldId: source.id },
    sourceTerritories,
    telemetry: sourceTerritories.map(({ snapshot }) => territoryReadinessTelemetry(snapshot)),
    temporalHistory: timeHistory,
  };
  await mkdir(GENERATED, { recursive: true });
  await mkdir(EXPORTS, { recursive: true });
  await writeFile(resolve(EXPORTS, "territory-award-readiness-v1-full.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  await writeFile(resolve(GENERATED, "territory-award-readiness-v1-summary.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  await writeFile(resolve(ROOT, "TERRITORY_AWARD_READINESS_V1_REPORT.md"), report(result), "utf8");
  return result;
}

void run().then((result) => {
  process.stdout.write(`${JSON.stringify({
    flags: result.featureFlags,
    growth: result.growth.healthy.map(({ snapshot, teamCount }) => ({ observed: snapshot.observedState, readiness: snapshot.readinessState, teamCount })),
    source: result.source,
  }, null, 2)}\n`);
}).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
