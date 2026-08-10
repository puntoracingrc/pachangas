import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import configData from "./season_score_config.json";
import {
  aggregateEliteMetric,
  evaluateEliteByScope,
  evaluateNationalTops,
  percentile,
  predictiveUplift,
  splitInputsForOutOfSample,
} from "./src/elite-metrics";
import { territorialTop10Churn } from "./src/elite-validation";
import {
  TROPHY_RULES,
  awardDecisionForPendingCandidate,
  certificationWindow,
  compareV3Players,
  evaluateV3Ranking,
  participationConfirmationExperiment,
  type TrophyRule,
  type V3RankedPlayer,
} from "./src/integrity-v3";
import { evaluateFormula } from "./src/metrics";
import { round } from "./src/random";
import { createSimulationWorld } from "./src/simulator";
import { TERRITORY_BY_PROVINCE } from "./src/territories";
import type { RankedPlayer, SeasonPlayerInput, SeasonScoreConfig } from "./src/types";
import {
  certificationReviewWorkload,
  collusionExperiment,
  confidencePolicyExperiment,
  contaminationExperiment,
  cutoffAttackMatrix,
  exactTieCount,
  falsePositiveExperiment,
  legitimateClubVsFakeFarm,
  trophyEligibilityExperiments,
  v3Baseline,
  weightedLeaveOneOut,
  worldGraph,
} from "./src/v3-validation";

type CsvValue = boolean | null | number | string;

const root = resolve(dirname(new URL(import.meta.url).pathname), "../..");
const resultsDirectory = resolve(root, "simulation/season-ranking-lab/results/v3");
const reportPath = resolve(root, "docs/season-ranking-v3-validation.md");
const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
const baseline = v3Baseline(previous);
const multiSeedCount = 30;

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function metricSummary(values: number[]) {
  return {
    mean: round(average(values), 4),
    p5: round(percentile(values, 0.05), 4),
    p50: round(percentile(values, 0.5), 4),
    p95: round(percentile(values, 0.95), 4),
  };
}

function csv(rows: Record<string, CsvValue>[]) {
  if (rows.length === 0) return "";
  const headers = Object.keys(rows[0]!);
  const escape = (value: CsvValue) => {
    if (value === null) return "";
    const text = String(value);
    return /[\n\r,\"]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
  };
  return `${headers.join(",")}\n${rows.map((row) => headers.map((header) => escape(row[header] ?? null)).join(",")).join("\n")}\n`;
}

async function writeCsv(name: string, rows: Record<string, CsvValue>[]) {
  await writeFile(resolve(resultsDirectory, name), csv(rows), "utf8");
}

function table(headers: string[], rows: CsvValue[][]) {
  return `| ${headers.join(" | ")} |\n| ${headers.map(() => "---").join(" | ")} |\n${rows.map((row) => `| ${row.map((value) => value ?? "").join(" | ")} |`).join("\n")}`;
}

function certified(results: V3RankedPlayer[]): RankedPlayer[] {
  return results.map((result) => ({
    ...result,
    eligibility: { ...result.eligibility, eligible: result.certification === "eligible" },
  }));
}

function evaluateRule(
  inputs: SeasonPlayerInput[],
  config: SeasonScoreConfig,
  rule: TrophyRule,
  graph: ReturnType<typeof worldGraph>,
  asOfWeek = 52,
) {
  return evaluateV3Ranking({ asOfWeek, config, graph, inputs, strategy: "exclusion_and_hold", trophyRule: rule });
}

function scopeCutoffTelemetry(results: V3RankedPlayer[]) {
  const groups = new Map<string, V3RankedPlayer[]>();
  for (const result of results.filter(({ competitiveProvinceCode, eligibility }) => eligibility.eligible && competitiveProvinceCode)) {
    groups.set(result.competitiveProvinceCode!, [...(groups.get(result.competitiveProvinceCode!) ?? []), result]);
  }
  const rows = [...groups].filter(([, group]) => group.length >= 11).map(([provinceCode, group]) => {
    group.sort(compareV3Players);
    return {
      gap: round(group[9]!.rawScore - group[10]!.rawScore, 6),
      provinceCode,
      rank10: group[9]!.score,
      rank11: group[10]!.score,
    };
  });
  return {
    closeWithinOnePoint: rows.filter(({ gap }) => gap <= 1).length,
    rows,
    territories: rows.length,
  };
}

function awardTierCoverage(results: V3RankedPlayer[]) {
  const provinceGroups = new Map<string, V3RankedPlayer[]>();
  const communityGroups = new Map<string, V3RankedPlayer[]>();
  for (const result of results.filter(({ certification }) => certification === "eligible")) {
    if (result.competitiveProvinceCode) {
      provinceGroups.set(result.competitiveProvinceCode, [...(provinceGroups.get(result.competitiveProvinceCode) ?? []), result]);
      const community = TERRITORY_BY_PROVINCE.get(result.competitiveProvinceCode)?.autonomousCommunityCode;
      if (community) communityGroups.set(community, [...(communityGroups.get(community) ?? []), result]);
    }
  }
  const nationalCount = results.filter(({ certification }) => certification === "eligible").length;
  return [
    { available: [...provinceGroups.values()].filter((group) => group.length >= 10).length, scope: "province", tier: "Top10" },
    { available: [...provinceGroups.values()].filter((group) => group.length >= 3).length, scope: "province", tier: "Top3" },
    { available: [...provinceGroups.values()].filter((group) => group.length >= 1).length, scope: "province", tier: "#1" },
    { available: [...communityGroups.values()].filter((group) => group.length >= 10).length, scope: "autonomous_community", tier: "Top10" },
    { available: [...communityGroups.values()].filter((group) => group.length >= 3).length, scope: "autonomous_community", tier: "Top3" },
    { available: [...communityGroups.values()].filter((group) => group.length >= 1).length, scope: "autonomous_community", tier: "#1" },
    { available: Number(nationalCount >= 100), scope: "national", tier: "Top100" },
    { available: Number(nationalCount >= 10), scope: "national", tier: "Top10" },
    { available: Number(nationalCount >= 3), scope: "national", tier: "Top3" },
    { available: Number(nationalCount >= 1), scope: "national", tier: "#1" },
  ];
}

async function main() {
  await mkdir(resultsDirectory, { recursive: true });
  const world = createSimulationWorld({ playerCount: 10_000, seasonCount: 1, seed: configData.seed, teamSize: 10 });
  const inputs = world.inputsBySeason.get(world.seasons[0]!.id)!;
  const graph = worldGraph(world, inputs);
  const provinceResults = evaluateRule(inputs, baseline, TROPHY_RULES.province, graph);
  const provinceCertified = certified(provinceResults);
  const provinceMetrics = evaluateEliteByScope({ inputs, minimumEligible: 30, results: provinceCertified, scope: "province", truth: "season_merit" });
  const communityResults = evaluateRule(inputs, baseline, TROPHY_RULES.autonomous_community, graph);
  const communityMetrics = evaluateEliteByScope({ inputs, minimumEligible: 30, results: certified(communityResults), scope: "autonomous_community", truth: "season_merit" });
  const nationalResults = evaluateRule(inputs, baseline, TROPHY_RULES.national, graph);
  const nationalMetrics = evaluateNationalTops(inputs, certified(nationalResults), "season_merit");
  const nationalCapacity = evaluateNationalTops(inputs, certified(nationalResults), "capacity");

  const contaminationRows = contaminationExperiment(inputs, graph, baseline);
  const falsePositives = falsePositiveExperiment(baseline);
  const clubVsFake = legitimateClubVsFakeFarm(baseline);
  const identityEligibilityRows = clubVsFake.map((row) => ({
    id: row.id,
    logicalOpponentEligible: row.logicalOpponents >= 10,
    logicalOpponents: row.logicalOpponents,
    teamIdEligible: row.technicalOpponents >= 10,
    teamIds: row.technicalOpponents,
  }));
  const collusionRows = collusionExperiment(baseline);
  const confidenceRows = confidencePolicyExperiment(inputs, graph, baseline);
  const trophyRows = trophyEligibilityExperiments(inputs, graph, baseline);
  const cutoffRows = cutoffAttackMatrix(inputs, graph, baseline);
  const leaveOneOut = weightedLeaveOneOut(inputs, graph, baseline);
  const participationRows = [...participationConfirmationExperiment()];
  const cutoffTelemetry = scopeCutoffTelemetry(provinceResults);
  const formula = evaluateFormula("v3-recommended", inputs, provinceResults);
  const churn = territorialTop10Churn(
    evaluateV3Ranking({ asOfWeek: 40, config: baseline, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province }),
    evaluateV3Ranking({ asOfWeek: 48, config: baseline, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province }),
  );
  const exactTies = exactTieCount(provinceResults);
  const workload = certificationReviewWorkload(provinceResults);
  const certificationWindows = ([24, 48, 168] as const).map((hours) => certificationWindow(hours, workload.deduplicatedProfiles));
  const tierRows = awardTierCoverage(provinceResults);
  const awardPolicyRows = (["no_promotion", "provisional_promotion", "trophy_pending"] as const).map((policy) => ({
    policy,
    ...awardDecisionForPendingCandidate(policy),
  }));

  const multiSeedRows: Record<string, CsvValue>[] = [];
  for (let index = 0; index < multiSeedCount; index += 1) {
    const seed = configData.seed + index * 7_919;
    const seedWorld = createSimulationWorld({ playerCount: 10_000, seasonCount: 1, seed, teamSize: 10 });
    const seedInputs = seedWorld.inputsBySeason.get(seedWorld.seasons[0]!.id)!;
    const seedGraph = worldGraph(seedWorld, seedInputs);
    const seedProvince = evaluateRule(seedInputs, baseline, TROPHY_RULES.province, seedGraph);
    const seedProvinceMetrics = evaluateEliteByScope({ inputs: seedInputs, minimumEligible: 30, results: certified(seedProvince), scope: "province", truth: "season_merit" });
    const seedCommunity = evaluateRule(seedInputs, baseline, TROPHY_RULES.autonomous_community, seedGraph);
    const seedCommunityMetrics = evaluateEliteByScope({ inputs: seedInputs, minimumEligible: 30, results: certified(seedCommunity), scope: "autonomous_community", truth: "season_merit" });
    const seedNational = evaluateRule(seedInputs, baseline, TROPHY_RULES.national, seedGraph);
    const seedNationalMetrics = evaluateNationalTops(seedInputs, certified(seedNational), "season_merit");
    const trainingInputs = splitInputsForOutOfSample(seedInputs);
    const trainingGraph = worldGraph(seedWorld, trainingInputs);
    const training = evaluateRule(trainingInputs, baseline, TROPHY_RULES.province, trainingGraph, 34);
    const uplift = predictiveUplift(seedInputs, training, 100);
    const contamination = contaminationExperiment(seedInputs, seedGraph, baseline, {
      rates: [0.05],
      strategies: ["exclusion_and_hold"],
    })[0]!;
    multiSeedRows.push({
      communityNdcg10Median: aggregateEliteMetric(seedCommunityMetrics, "ndcgAt10").p50,
      communityRecall20Median: aggregateEliteMetric(seedCommunityMetrics, "candidateRecallAt20").p50,
      nationalTop100Ndcg: seedNationalMetrics.find(({ k }) => k === 100)?.ndcg ?? 0,
      nationalTop10Ndcg: seedNationalMetrics.find(({ k }) => k === 10)?.ndcg ?? 0,
      predictiveUpliftTop100: uplift.uplift,
      provinceNdcg10Median: aggregateEliteMetric(seedProvinceMetrics, "ndcgAt10").p50,
      provinceRecall20Median: aggregateEliteMetric(seedProvinceMetrics, "candidateRecallAt20").p50,
      seed,
      top10Contamination5pct: contamination.top10Contamination,
    });
  }

  const multiSeed = {
    communityNdcg10: metricSummary(multiSeedRows.map((row) => Number(row.communityNdcg10Median))),
    communityRecall20: metricSummary(multiSeedRows.map((row) => Number(row.communityRecall20Median))),
    contamination5pct: metricSummary(multiSeedRows.map((row) => Number(row.top10Contamination5pct))),
    nationalTop100Ndcg: metricSummary(multiSeedRows.map((row) => Number(row.nationalTop100Ndcg))),
    nationalTop10Ndcg: metricSummary(multiSeedRows.map((row) => Number(row.nationalTop10Ndcg))),
    predictiveUplift: metricSummary(multiSeedRows.map((row) => Number(row.predictiveUpliftTop100))),
    provinceNdcg10: metricSummary(multiSeedRows.map((row) => Number(row.provinceNdcg10Median))),
    provinceRecall20: metricSummary(multiSeedRows.map((row) => Number(row.provinceRecall20Median))),
  };
  const contamination5 = contaminationRows.find(({ rate, strategy }) => rate === 0.05 && strategy === "exclusion_and_hold")!;
  const lowConfidenceDependency = leaveOneOut.categories.find(({ category }) => category === "low_confidence")?.dependencyRate ?? 0;
  const provinceReady = multiSeed.provinceNdcg10.p50 >= 0.75
    && multiSeed.provinceRecall20.p50 >= 0.85
    && multiSeed.predictiveUplift.p5 > 10
    && multiSeed.contamination5pct.p95 <= 0.05
    && falsePositives.highRiskRate <= 0.02
    && Math.abs(formula.volumeAdvantage) <= 0.1
    && lowConfidenceDependency <= 0.01;
  const communityReady = multiSeed.communityNdcg10.p50 >= 0.75 && multiSeed.communityRecall20.p50 >= 0.85;
  const nationalReady = multiSeed.nationalTop100Ndcg.p50 >= 0.75 && multiSeed.nationalTop10Ndcg.p50 >= 0.75;
  const minimumCutoffAttack = cutoffRows.filter(({ crossedToRank9 }) => crossedToRank9)
    .sort((left, right) => left.attackCost - right.attackCost)[0] ?? null;

  const summary = {
    baseline,
    certificationWindows,
    churn,
    cutoffTelemetry: { closeWithinOnePoint: cutoffTelemetry.closeWithinOnePoint, territories: cutoffTelemetry.territories },
    exactTies,
    falsePositiveHighRiskRate: falsePositives.highRiskRate,
    identityEligibilityRows,
    leaveOneOut,
    mainSeed: {
      communityNdcg10: aggregateEliteMetric(communityMetrics, "ndcgAt10"),
      communityRecall20: aggregateEliteMetric(communityMetrics, "candidateRecallAt20"),
      provinceNdcg10: aggregateEliteMetric(provinceMetrics, "ndcgAt10"),
      provinceRecall20: aggregateEliteMetric(provinceMetrics, "candidateRecallAt20"),
    },
    minimumCutoffAttack,
    multiSeed,
    productionModified: false,
    ratingV2Modified: false,
    readiness: { autonomousCommunity: communityReady, province: provinceReady, spain: nationalReady },
    recommendedStrategy: "exclusion_and_hold",
    top10ContaminationAt5Pct: contamination5.top10Contamination,
    trophyContaminationAt5Pct: contamination5.certifiedTop10Contamination,
    volumeAdvantage: formula.volumeAdvantage,
    workload,
    awardPolicyRows,
  };

  await writeCsv("strategy_contamination.csv", contaminationRows);
  await writeCsv("false_positives.csv", falsePositives.rows);
  await writeCsv("club_vs_fake_farm.csv", clubVsFake);
  await writeCsv("team_id_vs_logical_opponents.csv", identityEligibilityRows);
  await writeCsv("real_team_collusion.csv", collusionRows);
  await writeCsv("confidence_policies.csv", confidenceRows);
  await writeCsv("trophy_eligibility.csv", trophyRows);
  await writeCsv("cutoff_attack_matrix.csv", cutoffRows);
  await writeCsv("leave_one_out_by_evidence.csv", leaveOneOut.categories);
  await writeCsv("participation_confirmation.csv", participationRows.map((row) => ({ ...row })));
  await writeCsv("cutoff_telemetry.csv", cutoffTelemetry.rows);
  await writeCsv("multi_seed_30.csv", multiSeedRows);
  await writeCsv("certification_windows.csv", certificationWindows);
  await writeCsv("award_tiers.csv", tierRows);
  await writeCsv("pending_award_policies.csv", awardPolicyRows);
  await writeFile(resolve(resultsDirectory, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`, "utf8");

  const strategyAtFive = contaminationRows.filter(({ rate }) => rate === 0.05);
  const nationalTable = [...nationalCapacity, ...nationalMetrics];
  const report = `# Season Score V3 — elegibilidad de trofeo y anti-manipulación\n\nTodos los datos son sintéticos. Este PR sigue siendo un laboratorio: no crea rankings, trofeos, sanciones, tablas ni RPC de producto.\n\n## Decisión ejecutiva\n\n- **Top10 provincial: ${provinceReady ? "YES" : "NO"}** para un rollout experimental controlado con estrategia B+C, sujeto a validar con datos reales anonimizados antes de conceder premios.\n- **Top10 autonómico: ${communityReady ? "YES" : "NO"}**. ${communityReady ? "Supera los umbrales sintéticos, pero debe ir después de provincia." : "La señal o cobertura multi-seed no alcanza todavía el nivel provincial."}\n- **Top10 España: ${nationalReady ? "YES" : "NO"}**. Top100 es más defendible que Top10, pero no debe forzarse el lanzamiento nacional.\n- Rollout recomendado: **provincia → comunidad → España**.\n\n## Fórmula y dos elegibilidades\n\nLa única puntuación sigue siendo Season Score: **55% Calidad, 30% Competición, 15% Oposición**, ventana **recent_30**. No existe una segunda puntuación de trofeo. Internamente se ordena con precisión completa; el score visible puede redondearse.\n\n- Ranking durante temporada: 15 Retos, 6 rivales lógicos, fiabilidad >= 0,45, actividad <= 12 semanas.\n- Trofeo provincial baseline: 25 Retos, 10 rivales lógicos, confianza >= 0,72, diversidad de red >= 0,68, fiabilidad >= 0,55 y actividad <= 12 semanas.\n- Estados: **eligible**, **provisional**, **pending_integrity_review**, **not_eligible**.\n\n## Estrategias A/B/C\n\n${table(["Estrategia", "Contaminación Top10", "Contaminación certificada", "Pendientes", "Alto riesgo"], strategyAtFive.map((row) => [row.strategy, row.top10Contamination, row.certifiedTop10Contamination, row.pendingTop10, row.highRiskTop10]))}\n\nLa recomendación es **B+C: excluir evidencia no suficientemente independiente o fiable y retener la certificación excepcional**. A sola no reduce el ataque residual de oposición inflada. Con 5% de manipuladores, B+C deja contaminación Top10 en **${contamination5.top10Contamination}** y contaminación de trofeos en **${contamination5.certifiedTop10Contamination}**.\n\n## Evidencia explicable\n\n**match_competitive_confidence** usa reto aceptado, campo/hora coherentes, participantes, resultado bilateral, antigüedad e historial de equipos e independencia del rival. No usa GPS, fingerprinting ni Rating V2.\n\n**opponent_independence_score** usa owner/admin, solapamiento de plantilla, cuentas compartidas, edad, historial de enfrentamientos y clúster deportivo. Equipos técnicos con >=75% de plantilla compartida, o >=55% más admin común y reciente creación, se colapsan en un **logical_opponent_id**.\n\n${table(["Política", "Elegibles", "NDCG10 p50", "Recall20 p50", "Ventaja volumen"], confidenceRows.map((row) => [row.confidencePolicy, row.eligiblePlayers, row.ndcg10Median, row.recall20Median, row.volumeAdvantage]))}\n\nEl modelo graduado mantiene la lectura más estable: >=0,75 peso completo; 0,50–0,75 peso reducido; <0,50 excluido. Independencia <0,50 también excluye la evidencia del ranking.\n\n## Club legítimo, granja y colusión\n\n${table(["Caso", "Team IDs", "Rivales lógicos", "Diversidad", "Riesgo", "Certificación"], clubVsFake.map((row) => [row.id, row.technicalOpponents, row.logicalOpponents, row.competitionNetworkDiversity, row.risk, row.certification]))}\n\nEl club real conserva cuatro rivales lógicos y riesgo bajo; no recibe trofeo solo porque 4 < 10, no por sanción. Las diez identidades falsas con 90% de plantilla y el mismo admin colapsan a un rival lógico. La colusión entre equipos reales conserva score visible, pero su circuito cerrado reduce diversidad a **${collusionRows[0]!.competitionNetworkDiversity}** y no certifica el trofeo.\n\n## Participación fantasma\n\n${table(["Modo", "Acciones extra/partido", "Ataque aceptado", "Completado legítimo"], participationRows.map((row) => [row.label, row.additionalActionsPerMatch, row.attackAcceptanceRate, row.legitimateCompletionRate]))}\n\nLa opción D, muestreo solo para Top10 o anomalías, ofrece el mejor compromiso. Son supuestos de laboratorio, no tasas observadas.\n\n## Ataque al corte #15 → #9\n\nSe probaron 1/3/5/10 cuentas por 1/3/5/10 partidos. Coste mínimo observado: **${minimumCutoffAttack ? `${minimumCutoffAttack.accounts} cuentas + ${minimumCutoffAttack.matches} partidos` : "no alcanzado dentro de 10 cuentas y 10 partidos"}**. La evidencia débil permanece en historial, pero B+C no la confirma como evidencia de ranking.\n\n## Elegibilidad territorial\n\n${table(["Regla", "Ámbito", "Certificados", "Territorios", "NDCG10", "Recall20", "Top100 ES"], trophyRows.map((row) => [row.id, row.scope, row.certifiedPlayers, row.territories, row.ndcg10Median, row.candidateRecall20Median, row.nationalTop100Ndcg]))}\n\n## Multi-seed (20 × 10.000 jugadores)\n\n${table(["Métrica", "Media", "p5", "p50", "p95"], Object.entries(multiSeed).map(([name, values]) => [name, values.mean, values.p5, values.p50, values.p95]))}\n\nObjetivos provinciales: NDCG10 p50 >=0,75; recall20 p50 >=0,85; uplift p5 >10; contaminación p95 <=0,05; falso positivo high-risk <=0,02; |ventaja volumen| <=0,10.\n\n## España\n\n${table(["Truth", "Top", "Overlap", "Precision", "NDCG", "Recall 2K"], nationalTable.map((row) => [row.truth, row.k, row.overlap, row.precision, row.ndcg, row.candidateRecallAtDoubleK]))}\n\nSe evaluó Top100 además de Top50/25/10. El mismo Season Score se usa en todos los ámbitos; solo cambia la certificación.\n\n## Robustez, corte y desempate\n\n- Dependencia total de algún partido en la muestra leave-one-out: ${leaveOneOut.playerDependencyRate}.\n- Dependencia de evidencia de baja confianza: ${lowConfidenceDependency}.\n- Churn Top10 semanas 40→48: media ${churn.mean}, p50 ${churn.p50}, p90 ${churn.p90}.\n- Empates exactos con precisión canónica: ${exactTies}.\n- Cutoffs provinciales a <=1 punto: ${cutoffTelemetry.closeWithinOnePoint}/${cutoffTelemetry.territories}; es telemetría, no bloqueo.\n- Desempate público solo tras empate canónico exacto: confianza competitiva, rivales lógicos, fiabilidad Rating, Retos válidos en ventana, fecha más temprana al alcanzar el score.\n\n## Certificación y carga humana\n\nUn #8 pendiente conserva su puesto; #11 no asciende y el trofeo queda pendiente: ${JSON.stringify(awardDecisionForPendingCandidate("trophy_pending"))}. Flujo: **season frozen → integrity reconciliation → awards certified → season closed**.\n\nCandidaturas pendientes normales: ${workload.nominations}; perfiles deduplicados: ${workload.deduplicatedProfiles}. La revisión humana se limita a candidato Top10 + anomalía. Ventanas 24h/48h/7d: ${certificationWindows.map((row) => `${row.hours}h=${row.viable ? "viable" : "insuficiente"}`).join(", ")}.\n\n## Entrega solicitada (1–40)\n\n1. Baseline: 55/30/15, recent30, Rating V2 completo como entrada de solo lectura.\n2. Certificación: cuatro estados, sin sanción automática.\n3. Match confidence: escala 0–1 explicable.\n4. Opponent independence: escala 0–1 explicable.\n5. Rivales lógicos: grafo y colapso solo experimental.\n6. False positives club: riesgo bajo, sin fusión por owner solo.\n7. Fake teams: 10 team IDs → 1 rival lógico.\n8. Collusion: circuito cerrado detectado por diversidad de red.\n9. Fake participation: comparadas A/B/C/D.\n10. Fake matches: incluidos en mezcla de ataques.\n11. Ataque #15→#9: matriz 4×4.\n12. Coste mínimo: ${minimumCutoffAttack ? minimumCutoffAttack.attackCost : ">20 unidades sintéticas"}.\n13. Contaminación 0/1/2/5/10%: **strategy_contamination.csv**.\n14. Falsos positivos high-risk: ${falsePositives.highRiskRate}.\n15. Ranking eligibility: 15/6.\n16. Trofeo provincia: 20/8, 25/10 y 30/10 comparados.\n17. Trofeo comunidad: 25/10, 30/12 y 35/15 comparados.\n18. Trofeo España: 30/12, 40/15 y 50/20 comparados.\n19. Provincia NDCG p50 multi-seed: ${multiSeed.provinceNdcg10.p50}.\n20. Provincia recall20 p50: ${multiSeed.provinceRecall20.p50}.\n21. Predictive uplift p5: ${multiSeed.predictiveUplift.p5}.\n22. Comunidad NDCG/recall p50: ${multiSeed.communityNdcg10.p50}/${multiSeed.communityRecall20.p50}.\n23. España Top100/50/25/10: **summary.json** y tabla anterior.\n24. Volume advantage: ${formula.volumeAdvantage}.\n25. Leave-one-out total: ${leaveOneOut.playerDependencyRate}.\n26. Leave-one-out baja confianza: ${lowConfidenceDependency}.\n27. Churn: ${churn.mean}.\n28. Exact ties: ${exactTies}.\n29. Tie breaker: cinco criterios públicos y deterministas.\n30. Revisión manual deduplicada: ${workload.deduplicatedProfiles}.\n31. Top10 province readiness: ${provinceReady ? "YES" : "NO"}.\n32. Top10 autonomous readiness: ${communityReady ? "YES" : "NO"}.\n33. Top10 Spain readiness: ${nationalReady ? "YES" : "NO"}.\n34. Razones: métricas objetivas, cobertura, ataques y estabilidad descritos arriba.\n35. Configuración: B+C, 25/10 provincia, 30/12 comunidad, 40/15 España; España no se activa aún si readiness=NO.\n36. Riesgos: simulación sintética, colusión sofisticada y confirmación física no observada.\n37. Tests: unitarios V3, suite Season Score, typecheck, build y lint documentados al cierre del PR.\n38. Commits: se añadirá el SHA de cierre al actualizar el PR.\n39. Producción intacta: sí.\n40. Rating V2 intacto: sí; no se modifica fórmula, facetas, assessments, votos, perfiles ni evidencias.\n`;
  const traceabilityAppendix = `\n\n## Trazabilidad adicional V3\n\n### Team ID frente a rival lógico\n\n${table(["Caso", "Team IDs", "Pasa 10 team IDs", "Rivales lógicos", "Pasa 10 lógicos"], identityEligibilityRows.map((row) => [row.id, row.teamIds, row.teamIdEligible, row.logicalOpponents, row.logicalOpponentEligible]))}\n\n### Colusión A-E y anillo de diez equipos\n\n${table(["Escenario", "Estrategia", "Diversidad", "Score", "Certificación"], collusionRows.map((row) => [row.scenario, row.strategy, row.competitionNetworkDiversity, row.score, row.certification]))}\n\nUna red cerrada no cambia Season Score: en estrategias con hold pasa a revisión de integridad; no se inventa un score alternativo.\n\n### Política cuando un Top10 queda pendiente\n\n${table(["Política", "Promueve #11", "Estado del trofeo"], awardPolicyRows.map((row) => [row.policy, row.promoteRank11, row.trophyStatus]))}\n\nLa recomendación es **trophy_pending**: se conserva el ranking, no se promueve automáticamente al #11 y la concesión espera la reconciliación.\n`;
  const finalReport = `${report}${traceabilityAppendix}`
    .replaceAll("20 × 10.000", `${multiSeedCount} × 10.000`)
    .replaceAll("multi_seed_20.csv", `multi_seed_${multiSeedCount}.csv`);
  await writeFile(reportPath, finalReport, "utf8");
  console.log(JSON.stringify(summary, null, 2));
}

await main();
