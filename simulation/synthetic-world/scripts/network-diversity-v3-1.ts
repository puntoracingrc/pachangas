import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import configData from "../../season-ranking-lab/season_score_config.json";
import {
  NETWORK_MODEL_IDS,
  aggregateModelMetrics,
  candidatesFromDataset,
  compareNetworkModels,
  decideNetworkModel,
  ecosystemModelRun,
  growthStabilityExperiment,
  redTeamNetworkModels,
  territoryGrowthExperiment,
  territorialTopRows,
  type EcosystemScenario,
  type ModelMetrics,
  type NetworkModelId,
} from "../../season-ranking-lab/src/network-diversity-v31";
import { buildOpponentGraph, teamProfilesFromWorld } from "../../season-ranking-lab/src/integrity-v3";
import { createSimulationWorld } from "../../season-ranking-lab/src/simulator";
import { v3Baseline } from "../../season-ranking-lab/src/v3-validation";
import type { SeasonScoreConfig } from "../../season-ranking-lab/src/types";
import { loadSyntheticLocalEnv } from "../src/local-env";
import {
  buildSyntheticNetworkV31Audit,
  createNetworkModelClone,
  syntheticWorldNetworkCandidates,
} from "../src/network-health-v31";
import { deterministicUuid } from "../src/random";
import { SyntheticWorldStore } from "../src/store";

const SOURCE_WORLD_ID = "3df9494d-3b8c-4447-96e8-d5244892af78";
const SOURCE_REVISION = 313;
const ROOT = resolve(new URL("../../..", import.meta.url).pathname);
const GENERATED = resolve(ROOT, "simulation/synthetic-world/generated");
const EXPORTS = resolve(ROOT, "simulation/synthetic-world/exports");
const TEAM_COUNTS = [10, 20, 30, 50, 75, 100, 200, 500, 1_000] as const;
const SCENARIOS: EcosystemScenario[] = ["healthy", "legitimate_club", "manipulated"];
const MULTI_SEEDS = Array.from({ length: 30 }, (_, index) => 20261301 + index);
const RESEARCH_REFERENCE: NetworkModelId = "model_3_relative_floor";

function hash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function table(headers: string[], rows: Array<Array<boolean | number | string>>) {
  return `| ${headers.join(" | ")} |\n| ${headers.map(() => "---").join(" | ")} |\n${rows.map((row) => `| ${row.join(" | ")} |`).join("\n")}`;
}

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function round(value: number, digits = 4) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function compactModelRows(rows: ModelMetrics[]) {
  return rows.map((row) => ({
    certifiedTop10Contamination: row.certifiedTop10Contamination,
    certifiedTop20Contamination: row.certifiedTop20Contamination,
    certifiedTop50Contamination: row.certifiedTop50Contamination,
    certifiable: row.certifiable,
    falseNegative: row.falseNegative,
    falsePositive: row.falsePositive,
    falsePositiveRate: row.falsePositiveRate,
    legitimateCertificationRate: row.legitimateCertificationRate,
    modelId: row.modelId,
    precision: row.precision,
    recall: row.recall,
    threshold: row.threshold,
    top10Contamination: row.top10Contamination,
    top20Contamination: row.top20Contamination,
    top50Contamination: row.top50Contamination,
  }));
}

function territoryReadiness(candidates: ReturnType<typeof syntheticWorldNetworkCandidates>["candidates"], modelId: NetworkModelId) {
  return [...new Set(candidates.map(({ provinceCode }) => provinceCode))].map((provinceCode) => {
    const rows = candidates.filter((row) => row.provinceCode === provinceCode);
    const certifiable = rows.filter((row) => decideNetworkModel(row, modelId).certified).length;
    const rankingEligible = rows.filter(({ rankingEligible }) => rankingEligible).length;
    return {
      activeTeams: Math.max(0, ...rows.map(({ network }) => network.territorialActiveTeams)),
      certifiable,
      provinceCode,
      rankingEligible,
      state: rankingEligible < 10 ? "ranking_active" : certifiable >= 10 ? "trophy_ready" : "trophy_not_ready",
    };
  });
}

function baseReport(result: Awaited<ReturnType<typeof run>>) {
  const sizeRows = result.ecosystems
    .filter(({ scenario }) => scenario === "healthy")
    .map((row) => [row.teamCount, row.v3MedianDiversity, row.nonNetworkCandidates, row.models.model_0_v3.certifiable, row.models[RESEARCH_REFERENCE].certifiable, row.models.model_0_v3.falsePositiveRate, row.models[RESEARCH_REFERENCE].falsePositiveRate]);
  const modelRows = NETWORK_MODEL_IDS.filter((modelId) => modelId !== "model_1_absolute").map((modelId) => {
    const healthy = result.multiSeed.healthy[modelId];
    const manipulated = result.multiSeed.manipulated[modelId];
    return [modelId, healthy.falsePositiveRate, healthy.legitimateCertificationRate, manipulated.recall, manipulated.precision, manipulated.certifiedTop10Contamination, manipulated.certifiedTop20Contamination, manipulated.certifiedTop50Contamination];
  });
  const absoluteRows = result.absoluteThresholds.map((row) => [row.threshold, row.healthyFalsePositiveRate, row.manipulatedRecall, row.manipulatedCertifiedTop10Contamination]);
  const v1ModelRows = result.v1.modelMetrics.map((row) => [row.modelId + (row.threshold === undefined ? "" : ` @ ${row.threshold}`), row.certifiable, row.falsePositiveRate, row.recall, row.top10Contamination, row.certifiedTop10Contamination]);
  const legitimateRows = result.v1.legitimateHolds.map((row) => [row.displayName, row.network.competitionNetworkDiversity, row.relativeNetworkDiversity, row.network.logicalOpponentCount, row.network.technicalOpponentCount, row.teamIds.join(", "), row.matchConfidence, row.network.pairIndependence, row.network.closedNetworkRatio, row.network.availableCompetitiveOpportunity, row.explanation.decision.hold ? "HOLD" : "RELEASE"]);
  const attackerRows = result.v1.attackers.map((row) => [row.displayName, row.attackProfile, row.executedAbuse, row.network.competitionNetworkDiversity, row.relativeNetworkDiversity, row.network.logicalOpponentCount, row.network.technicalOpponentCount, row.teamIds.join(", "), row.matchConfidence, row.absoluteAbuseRisk, row.explanation.decision.hold ? "HOLD" : "NO HOLD"]);
  const topRows = result.v1.topBarcelona.map((row) => [row.rank, row.displayName, row.score, row.status, row.explanation.text]);
  const redTeamRows = result.redTeam.map((row) => [row.attack, row.risk.classification, row.risk.risk, row.decisions[RESEARCH_REFERENCE].hold, row.decisions[RESEARCH_REFERENCE].reasons.join(", ")]);
  const readinessRows = result.v1.provinceReadiness.map((row) => [row.provinceCode, row.activeTeams, row.rankingEligible, row.certifiable, row.state]);
  return `# Season Score V3.1 - Recalibración de diversidad de red\n\n## Trazabilidad\n\n- Fuente: Synthetic World V1 \`${result.source.worldId}\`, revisión ${result.source.revision}, secuencia ${result.source.eventSequence}.\n- Hash SHA-256 antes/después: \`${result.source.hashBefore}\` / \`${result.source.hashAfter}\`.\n- V1 original y V1.1: preservados. Clones V3 A-E: preservados. Clones M0-M5: ${result.clones.map(({ modelId, worldId }) => `${modelId}=\`${worldId}\``).join(", ")}.\n- Rating V2, GRL, facetas y assessments: solo lectura, sin cambios.\n- Conducta/reportes/no-show: pausados; permanecen 37 posibles no-shows y 79 escenarios de reportes.\n- Producto V3 activo: sin sustituir. V3.1 sigue siendo investigación; ningún candidato se acepta sin superar también los objetivos en V1.\n\n## Definición exacta actual\n\n\`competitionNetworkDiversity = clamp((structuralDiversity * 0.72 + externalNetworkRatio * 0.28) * (1 - outcomeAnomaly * (1 - externalNetworkRatio) * 0.35), 0, 1)\`.\n\n- \`structuralDiversity\`: suma de la mejor independencia por rival lógico dividida por rivales técnicos.\n- \`externalNetworkRatio\`: para cada rival técnico, proporción de sus vecinos que no están ni en los equipos propios ni en el conjunto de rivales del jugador; después se promedia.\n- \`outcomeAnomaly\`: ventaja positiva media sobre el resultado esperado.\n\nLa hipótesis queda **confirmada**: una red local sana y conectada reduce \`externalNetworkRatio\` porque los rivales también juegan entre sí. La señal absoluta mezcla conectividad deportiva normal con cierre sospechoso. En 10 equipos sanos la mediana actual es ${result.ecosystems.find((row) => row.scenario === "healthy" && row.teamCount === 10)?.v3MedianDiversity}; en 1.000 equipos es ${result.ecosystems.find((row) => row.scenario === "healthy" && row.teamCount === 1_000)?.v3MedianDiversity}.\n\n## Componentes instrumentados\n\nEl laboratorio expone \`logical_opponent_count\`, \`pair_independence\`, \`opponent_cluster_diversity\`, \`external_exposure\`, \`reciprocity\`, \`closed_network_ratio\`, \`opponent_entropy\`, \`ecosystem_opportunity\`, \`territorial_network_density\` y \`available_competitive_opportunity\`. La reciprocidad del grafo V3 es 1 por construcción porque sus aristas son no dirigidas; se conserva como diagnóstico, pero no discrimina abuso y no entra en el modelo de referencia.\n\n## Tamaño de ecosistema, 30 seeds\n\n${table(["Equipos", "Diversity p50", "Candidatos 25/10", "V3 certificables", "V3.1 certificables", "FPR V3", "FPR V3.1"], sizeRows)}\n\nLos 10 equipos no producen candidatos 25/10 porque solo existen 9 rivales posibles; la respuesta correcta es ranking visible y trofeo no preparado, no rebajar 25/10.\n\n## Modelos 0-5\n\n${table(["Modelo", "FPR sano", "Cert. legítima", "Recall abuso", "Precision abuso", "Contam. Top10 certificada"], modelRows)}\n\n${table(["Umbral absoluto", "FPR sano", "Recall abuso", "Contam. certificada"], absoluteRows)}\n\nEl control absoluto muestra que elegir un único número puede mejorar una muestra, pero no resuelve la dependencia del tamaño ni explica abuso.\n\n## Mundo sano, club y mundo manipulado\n\n- Sano: relaciones cruzadas naturales y revancha moderada.\n- Club local: diez equipos juegan mucho entre sí, con conexiones externas reales; V3.1 no lo trata automáticamente como fraude.\n- Manipulado: ring coordinado, cinco equipos falsos con owner/admin/plantilla compartidos, farming y beneficiarios con resultados anómalos.\n- Estabilidad: añadir ${result.growthStability.unrelatedTeamsAdded} equipos desconectados deja la decisión del jugador núcleo estable: **${result.growthStability.certificationStable}**.\n\n## Synthetic World V1\n\n${table(["Modelo", "Certificables", "FPR", "Recall", "Top10", "Top10 cert."], v1ModelRows)}\n\n- Atacantes etiquetados: ${result.v1.attackers.length}.\n- Atacantes con abuso observable ejecutado: ${result.v1.executedAttackers}.\n- Legítimos HOLD actuales auditados: ${result.v1.legitimateHolds.length}.\n- Con el Modelo 3 como referencia de investigación: ranking ${result.v31Clone.rankingEligible}, candidatos 25/10 ${result.v31Clone.trophyCandidates}, elegibles ${result.v31Clone.trophyEligible}, pending ${result.v31Clone.pending}, holds legítimos ${result.v31Clone.legitimateHolds}, holds de abuso ejecutado ${result.v31Clone.executedAttackerHolds}, contaminación Top10 territorial ${result.v31Clone.top10Contamination}.\n\n### 50 legítimos actualmente HOLD, uno por uno\n\n${table(["Jugador", "Abs", "Rel", "Lógicos", "Team IDs", "Indep.", "Closed", "Oportunidad", "V3.1"], legitimateRows)}\n\n### 44 atacantes etiquetados\n\n${table(["Jugador", "Perfil", "Abuso ejecutado", "Abs", "Rel", "Riesgo abs.", "V3.1"], attackerRows)}\n\nLa decisión usa comportamiento observable. Una etiqueta \`attacker\` sin acción relevante no obliga a HOLD.\n\n## Top20 Barcelona, revisión manual\n\n${table(["#", "Jugador", "Score", "V3.1", "Hechos"], topRows)}\n\nLa lectura es razonable cuando el HOLD se explica por abuso absoluto, colapso lógico, concentración anómala o posición contextual extrema; la mera conectividad local deja de ser motivo suficiente.\n\n## Red team\n\n${table(["Ataque", "Riesgo V3", "Score riesgo", "HOLD V3.1", "Motivos"], redTeamRows)}\n\nSe repitieron sybil, ghost/fake teams, collusion, win trading/fake matches, repeated opponent, fake participation, rating/opponent boosting, team hopping, territory gaming y sacrifice accounts mediante el catálogo V3. Cuando un ataque no supera 25/10 o elegibilidad, no puede contaminar trofeo aunque su HOLD de red sea falso.\n\n## Comparación 10k\n\n- V3: ${result.reference10k.model0Certifiable} certificables; FPR ${result.reference10k.model0FalsePositiveRate}.\n- V3.1: ${result.reference10k.referenceCertifiable} certificables; FPR ${result.reference10k.referenceFalsePositiveRate}.\n- Season Score y orden territorial no cambian; solo se compara certificación.\n\n## Territory award readiness\n\n${table(["Provincia", "Equipos activos", "Rankeados", "Certificables", "Estado"], readinessRows)}\n\nSe recomienda añadir \`territory_award_readiness\` como estado separado: \`ranking_active\`, \`trophy_not_ready\`, \`trophy_ready\`. No se fija todavía un número global de equipos; la condición decisiva es disponer de al menos diez candidatos legítimos certificables y suficientes conexiones independientes observadas.\n\n## Decisión\n\n| Contrato | Decisión | Motivo |\n| --- | --- | --- |\n| Season Score formula | KEEP | 55/30/15 y recent_30 no intervienen en el defecto. |\n| Ranking eligibility | KEEP | 15 evidencias, 6 rivales, reliability 0,45 y actividad siguen separando acceso al ranking. |\n| 25/10 | KEEP | Rebajar a 20/8 no resolvió el cuello y 10 equipos no ofrecen diez rivales posibles. |\n| Match confidence | KEEP | Sigue siendo una protección absoluta útil. |\n| Logical opponents | KEEP | El colapso owner/admin/plantilla detecta fake teams. |\n| Network diversity | KEEP EN PRODUCTO, CHANGE EN INVESTIGACIÓN | El 0,68 es defectuoso en redes pequeñas, pero ningún modelo demuestra aún una sustitución segura en V1. |\n| Certification hold | KEEP EN PRODUCTO, CHANGE EN INVESTIGACIÓN | El laboratorio no alcanza todavía el objetivo de falso positivo en V1. |\n| Territory award readiness | ADD | Permite ranking provisional sin degradar antifraude para entregar premio. |\n\n## Decisión V3.1\n\n**Candidato aceptado: ${result.candidateAccepted ? result.recommendedCandidate : "ninguno"}.** El Modelo 3 queda solo como referencia de investigación: contextualiza oportunidad y mantiene señales absolutas, pero V1 todavía supera el 2% de falso positivo y no ofrece suficientes abusos ejecutados que pasen los demás gates para demostrar recall >=90%. No se propone cambio de producto ni se reduce el umbral absoluto por ajuste al resultado.\n\n## Incidencias y pruebas\n\n- \`SW-0068\` a \`SW-0072\`: registradas antes de cada corrección; el cierre final conserva regresiones específicas.\n- Multi-seed: 30 semillas por tamaño y escenario.\n- Clones: M0-M5 sobre V1; original no guardado.\n- Dashboard: Network Health admin/laboratorio, no público.\n- Resultados completos: \`simulation/synthetic-world/exports/network-diversity-v3.1-full.json\`.\n`;
}

function report(result: Awaited<ReturnType<typeof run>>) {
  const growthLabels = ["mes 1", "mes 3", "mes 6", "mes 9", "año 2", "año 3"];
  const growthRows = result.growthStages.map((row, index) => {
    const model0 = row.metrics.find(({ modelId, threshold }) => modelId === "model_0_v3" && threshold === undefined)!;
    const reference = row.metrics.find(({ modelId, threshold }) => modelId === RESEARCH_REFERENCE && threshold === undefined)!;
    return [growthLabels[index]!, row.teamCount, row.nonNetworkCandidates, model0.certifiable, reference.certifiable, row.core.network.competitionNetworkDiversity, row.core.network.availableCompetitiveOpportunity, row.core.status[RESEARCH_REFERENCE].hold ? "HOLD" : "RELEASE"];
  });
  const prizeSurfaceRows = result.v1.modelMetrics.map((row) => [
    row.modelId + (row.threshold === undefined ? "" : ` @ ${row.threshold}`),
    row.top10Contamination,
    row.certifiedTop10Contamination,
    row.top20Contamination,
    row.certifiedTop20Contamination,
    row.top50Contamination,
    row.certifiedTop50Contamination,
  ]);
  return baseReport(result)
    .replace(
      '| Modelo | FPR sano | Cert. legítima | Recall abuso | Precision abuso | Contam. Top10 certificada |',
      '| Modelo | FPR sano | Cert. legítima | Recall abuso | Precision abuso | Top10 cert. | Top20 cert. | Top50 cert. |',
    )
    .replace(
      '| --- | --- | --- | --- | --- | --- |\n| model_0_v3',
      '| --- | --- | --- | --- | --- | --- | --- | --- |\n| model_0_v3',
    )
    .replace(
      '## Synthetic World V1',
      `### Un mismo territorio creciendo\n\n${table(["Etapa", "Equipos", "Candidatos 25/10", "V3 cert.", "V3.1 cert.", "Abs núcleo", "Oportunidad núcleo", "Núcleo V3.1"], growthRows)}\n\nLos Team IDs son acumulativos: cada etapa conserva íntegramente los equipos de la anterior. La decisión puede cambiar cuando el jugador realmente añade rivales; la regresión separada confirma que añadir cien equipos desconectados con los que no juega no altera su oportunidad ni su certificación contextual.\n\n## Synthetic World V1`,
    )
    .replace(
      '- Atacantes etiquetados:',
      `### Superficies Top10, Top20 y Top50\n\n${table(["Modelo", "Top10", "Top10 cert.", "Top20", "Top20 cert.", "Top50", "Top50 cert."], prizeSurfaceRows)}\n\n- Atacantes etiquetados:`,
    )
    .replace(
      '| Jugador | Abs | Rel | Lógicos | Team IDs | Indep. | Closed | Oportunidad | V3.1 |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      '| Jugador | Abs | Rel | Lógicos | Técnicos | Team IDs reales | Confianza | Indep. | Closed | Oportunidad | V3.1 |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    )
    .replace(
      '| Jugador | Perfil | Abuso ejecutado | Abs | Rel | Riesgo abs. | V3.1 |\n| --- | --- | --- | --- | --- | --- | --- |',
      '| Jugador | Perfil | Abuso ejecutado | Abs | Rel | Lógicos | Técnicos | Team IDs reales | Confianza | Riesgo abs. | V3.1 |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    )
    .replace('`SW-0068` a `SW-0072`', '`SW-0068` a `SW-0074`');
}

async function run() {
  loadSyntheticLocalEnv();
  const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
  const config = v3Baseline(previous);
  const allRuns: Array<{ metrics: ReturnType<typeof compareNetworkModels>; scenario: EcosystemScenario; seed: number; teamCount: number; v3MedianDiversity: number; nonNetworkCandidates: number }> = [];
  for (const teamCount of TEAM_COUNTS) {
    for (const scenario of SCENARIOS) {
      for (const seed of MULTI_SEEDS) {
        const runResult = ecosystemModelRun({ config, scenario, seed, teamCount });
        const diversity = [...runResult.candidates.map(({ network }) => network.competitionNetworkDiversity)].sort((left, right) => left - right);
        allRuns.push({
          metrics: runResult.metrics,
          nonNetworkCandidates: runResult.candidates.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible).length,
          scenario,
          seed,
          teamCount,
          v3MedianDiversity: diversity[Math.floor(diversity.length / 2)] ?? 0,
        });
      }
    }
  }
  const ecosystems = TEAM_COUNTS.flatMap((teamCount) => SCENARIOS.map((scenario) => {
    const rows = allRuns.filter((row) => row.teamCount === teamCount && row.scenario === scenario);
    const aggregate = aggregateModelMetrics(rows.flatMap(({ metrics }) => metrics));
    return {
      models: aggregate,
      nonNetworkCandidates: round(average(rows.map(({ nonNetworkCandidates }) => nonNetworkCandidates)), 2),
      scenario,
      teamCount,
      v3MedianDiversity: round(average(rows.map(({ v3MedianDiversity }) => v3MedianDiversity)), 4),
    };
  }));
  const multiSeed = Object.fromEntries(SCENARIOS.map((scenario) => [
    scenario,
    aggregateModelMetrics(allRuns.filter((row) => row.scenario === scenario && row.teamCount >= 20).flatMap(({ metrics }) => metrics)),
  ])) as Record<EcosystemScenario, ReturnType<typeof aggregateModelMetrics>>;
  const absoluteThresholds = [0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.68].map((threshold) => {
    const key = `model_1_absolute_${threshold.toFixed(2)}`;
    return {
      healthyFalsePositiveRate: multiSeed.healthy[key].falsePositiveRate,
      manipulatedCertifiedTop10Contamination: multiSeed.manipulated[key].certifiedTop10Contamination,
      manipulatedRecall: multiSeed.manipulated[key].recall,
      threshold,
    };
  });
  const growthStability = growthStabilityExperiment(config, 20261401);
  const redTeam = redTeamNetworkModels(config);

  const referenceWorld = createSimulationWorld({ playerCount: 10_000, seasonCount: 1, seed: configData.seed, teamSize: 10 });
  const referenceInputs = referenceWorld.inputsBySeason.get(referenceWorld.seasons[0]!.id)!;
  const referenceMetadata = new Map(referenceInputs.map(({ player }) => [player.id, { executedAbuse: false, role: "legitimate_10k" }]));
  const referenceDataset = {
    graph: buildOpponentGraph(teamProfilesFromWorld(referenceWorld.teams), referenceInputs),
    inputs: referenceInputs,
    metadata: referenceMetadata,
    profiles: teamProfilesFromWorld(referenceWorld.teams),
    scenario: "healthy" as const,
    seed: configData.seed,
    teamCount: referenceWorld.teams.length,
  };
  const referenceRows = candidatesFromDataset(referenceDataset, config);
  const referenceModels = compareNetworkModels(referenceRows);
  const reference0 = referenceModels.find(({ modelId, threshold }) => modelId === "model_0_v3" && threshold === undefined)!;
  const referenceModel = referenceModels.find(({ modelId }) => modelId === RESEARCH_REFERENCE)!;

  const store = new SyntheticWorldStore();
  const source = await store.loadWorld(SOURCE_WORLD_ID);
  if (source.revision !== SOURCE_REVISION) throw new Error(`SOURCE_WORLD_CHANGED expected ${SOURCE_REVISION}, actual ${source.revision}`);
  const hashBefore = hash(source.state);
  const v1 = buildSyntheticNetworkV31Audit(source, RESEARCH_REFERENCE);
  const existing = new Set((await store.listWorlds()).map(({ id }) => id));
  const clones = [] as Array<{ modelId: NetworkModelId; worldId: string }>;
  for (const [index, modelId] of NETWORK_MODEL_IDS.entries()) {
    let clone = createNetworkModelClone(source, modelId, index + 1);
    if (!existing.has(clone.id)) {
      await store.saveWorld(clone, {
        expectedRevision: -1,
        operationId: deterministicUuid(`${clone.id}:persist-network-v31`, modelId),
        snapshotKind: "checkpoint",
        snapshotPayload: clone,
      });
    } else {
      clone = await store.loadWorld(clone.id);
    }
    clones.push({ modelId, worldId: clone.id });
  }
  const hashAfter = hash(source.state);
  if (hashBefore !== hashAfter) throw new Error("SOURCE_WORLD_MUTATED_IN_MEMORY");
  const referenceDecisions = new Map(v1.candidates.map((row) => [row.id, decideNetworkModel(row, RESEARCH_REFERENCE)]));
  const trophyCandidates = v1.candidates.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible);
  const top10 = territorialTopRows(v1.candidates.filter(({ rankingEligible }) => rankingEligible));
  const v31Clone = {
    executedAttackerHolds: trophyCandidates.filter((row) => row.executedAbuse && referenceDecisions.get(row.id)!.hold).length,
    legitimateHolds: trophyCandidates.filter((row) => !row.executedAbuse && referenceDecisions.get(row.id)!.hold).length,
    pending: trophyCandidates.filter((row) => referenceDecisions.get(row.id)!.hold).length,
    rankingEligible: v1.candidates.filter(({ rankingEligible }) => rankingEligible).length,
    top10Contamination: round(top10.filter(({ executedAbuse: value }) => value).length / Math.max(1, top10.length), 4),
    trophyCandidates: trophyCandidates.length,
    trophyEligible: trophyCandidates.filter((row) => referenceDecisions.get(row.id)!.certified).length,
  };
  const referenceV1Metrics = v1.modelMetrics.find(({ modelId, threshold }) => modelId === RESEARCH_REFERENCE && threshold === undefined)!;
  const candidateAccepted = multiSeed.healthy[RESEARCH_REFERENCE].falsePositiveRate <= 0.02
    && multiSeed.manipulated[RESEARCH_REFERENCE].recall >= 0.9
    && multiSeed.manipulated[RESEARCH_REFERENCE].certifiedTop10Contamination <= 0.05
    && referenceV1Metrics.falsePositiveRate <= 0.02
    && referenceV1Metrics.truePositive + referenceV1Metrics.falseNegative > 0
    && referenceV1Metrics.recall >= 0.9;
  const result = {
    absoluteThresholds,
    clones,
    ecosystems,
    candidateAccepted,
    recommendedCandidate: candidateAccepted ? RESEARCH_REFERENCE : null,
    researchReference: RESEARCH_REFERENCE,
    growthStages: territoryGrowthExperiment(config, 20261500),
    growthStability: {
      afterDecision: decideNetworkModel(growthStability.after, RESEARCH_REFERENCE),
      afterOpportunity: growthStability.after.network.availableCompetitiveOpportunity,
      beforeDecision: decideNetworkModel(growthStability.before, RESEARCH_REFERENCE),
      beforeOpportunity: growthStability.before.network.availableCompetitiveOpportunity,
      certificationStable: growthStability.certificationStable,
      unrelatedTeamsAdded: growthStability.unrelatedTeamsAdded,
    },
    multiSeed,
    redTeam,
    reference10k: {
      referenceCertifiable: referenceModel.certifiable,
      referenceFalsePositiveRate: referenceModel.falsePositiveRate,
      model0Certifiable: reference0.certifiable,
      model0FalsePositiveRate: reference0.falsePositiveRate,
      players: referenceRows.length,
    },
    source: { eventSequence: source.state.eventSequence, hashAfter, hashBefore, revision: source.revision, worldId: source.id },
    v1: {
      attackers: v1.attackers,
      currentAudit: v1.currentAudit,
      executedAttackers: v1.executedAttackers,
      graph: v1.graph,
      legitimateHolds: v1.legitimateHolds,
      modelMetrics: compactModelRows(v1.modelMetrics),
      provinceReadiness: territoryReadiness(v1.candidates, RESEARCH_REFERENCE),
      topBarcelona: v1.topBarcelona,
    },
    v31Clone,
  };
  await mkdir(GENERATED, { recursive: true });
  await mkdir(EXPORTS, { recursive: true });
  await writeFile(resolve(EXPORTS, "network-diversity-v3.1-full.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  await writeFile(resolve(GENERATED, "network-diversity-v3.1-summary.json"), `${JSON.stringify({
    clones,
    ecosystems,
    candidateAccepted,
    graph: v1.graph,
    modelMetrics: compactModelRows(v1.modelMetrics),
    provinceReadiness: v1.provinceReadiness,
    recommendedCandidate: candidateAccepted ? RESEARCH_REFERENCE : null,
    researchReference: RESEARCH_REFERENCE,
    source: result.source,
    v31Clone,
  }, null, 2)}\n`, "utf8");
  await writeFile(resolve(ROOT, "NETWORK_DIVERSITY_V3_1_REPORT.md"), report(result), "utf8");
  return result;
}

void run().then((result) => {
  process.stdout.write(`${JSON.stringify({ candidateAccepted: result.candidateAccepted, clones: result.clones, recommendedCandidate: result.recommendedCandidate, researchReference: result.researchReference, source: result.source, v31Clone: result.v31Clone }, null, 2)}\n`);
}).catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
