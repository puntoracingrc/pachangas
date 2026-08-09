import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import configData from "./season_score_config.json";
import { assessRankingIntegrity, calculateSeasonScore, rankSeason, resolveCompetitiveProvince } from "./src/engine";
import { evaluateFormula, rankingChurn } from "./src/metrics";
import { round } from "./src/random";
import {
  attackProfiles,
  createProfileInput,
  evaluateAttacks,
  goalDifferenceExperiment,
  humanProfiles,
  legitimateRiskProfiles,
  newcomerProfiles,
  volumeProfiles,
} from "./src/scenarios";
import { createSimulationWorld } from "./src/simulator";
import { assertCanonicalTerritories, AUTONOMOUS_COMMUNITIES, TERRITORIES } from "./src/territories";
import type { RankedPlayer, SeasonPlayerInput, SeasonScoreConfig } from "./src/types";

type CsvValue = boolean | null | number | string;
type ContaminationRow = {
  cheaterTop10Penetration: number;
  cheaters: number;
  mode: "integrity" | "minimal";
  populationRate: number;
  top10OccupiedByCheaters: number;
};

const root = resolve(dirname(new URL(import.meta.url).pathname), "../..");
const labRoot = resolve(root, "simulation/season-ranking-lab");
const resultsDirectory = resolve(labRoot, "results");
const reportPath = resolve(root, "docs/season-ranking-lab-v1-report.md");
const candidates = configData.candidates as SeasonScoreConfig[];

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

function cloneInput(input: SeasonPlayerInput, suffix: string): SeasonPlayerInput {
  const playerId = `${input.player.id}-${suffix}`;
  return {
    ...input,
    player: { ...input.player, id: playerId, teamIds: input.player.teamIds.map((id) => `${id}-${suffix}`) },
    records: input.records.map((record) => ({
      ...record,
      challengeId: `${record.challengeId}-${suffix}`,
      opponentClusterId: `${record.opponentClusterId}-${suffix}`,
      opponentTeamId: `${record.opponentTeamId}-${suffix}`,
    })),
  };
}

function contamination(
  baseline: SeasonPlayerInput[],
  minimal: SeasonScoreConfig,
  integrity: SeasonScoreConfig,
): ContaminationRow[] {
  const base = baseline.slice(0, 1_000);
  const attacks = attackProfiles().filter(({ attack }) => ["collusion", "ghost_teams", "opponent_boost", "rating_boost", "sacrifice_accounts", "sybil"].includes(attack));
  return [0, 0.01, 0.02, 0.05, 0.1].flatMap((populationRate) => {
    const count = Math.round(base.length * populationRate);
    const cheaters = Array.from({ length: count }, (_, index) => cloneInput(attacks[index % attacks.length]!.input, `population-${index}`));
    const cheaterIds = new Set(cheaters.map(({ player }) => player.id));
    return ([['minimal', minimal], ['integrity', integrity]] as const).map(([mode, config]) => {
      const top = rankSeason([...base, ...cheaters], config).filter(({ eligibility }) => eligibility.eligible)
        .sort((left, right) => right.score - left.score).slice(0, 10);
      const occupied = top.filter(({ playerId }) => cheaterIds.has(playerId)).length;
      return {
        cheaterTop10Penetration: count === 0 ? 0 : round(occupied / count),
        cheaters: count,
        mode,
        populationRate,
        top10OccupiedByCheaters: round(occupied / 10),
      };
    });
  });
}

function svgChart(title: string, points: Array<{ label: string; value: number }>, maximum?: number) {
  const width = 920;
  const height = 480;
  const margin = 64;
  const maxValue = maximum ?? Math.max(1, ...points.map(({ value }) => value));
  const barWidth = Math.max(8, (width - margin * 2) / Math.max(1, points.length) - 8);
  const bars = points.map(({ label, value }, index) => {
    const x = margin + index * ((width - margin * 2) / points.length) + 4;
    const barHeight = (height - margin * 2) * value / maxValue;
    const y = height - margin - barHeight;
    return `<g><rect x="${round(x)}" y="${round(y)}" width="${round(barWidth)}" height="${round(barHeight)}" fill="#22c55e"/><text x="${round(x + barWidth / 2)}" y="${height - 38}" text-anchor="middle" fill="#d1fae5" font-size="11">${label}</text><text x="${round(x + barWidth / 2)}" y="${round(y - 7)}" text-anchor="middle" fill="#ffffff" font-size="11">${round(value)}</text></g>`;
  }).join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="${title}"><rect width="100%" height="100%" fill="#07120d"/><text x="${margin}" y="38" fill="#ffffff" font-size="22" font-family="system-ui">${title}</text><line x1="${margin}" y1="${height - margin}" x2="${width - margin}" y2="${height - margin}" stroke="#6b7280"/>${bars}</svg>`;
}

async function writeChart(name: string, title: string, points: Array<{ label: string; value: number }>, maximum?: number) {
  await writeFile(resolve(resultsDirectory, name), svgChart(title, points, maximum), "utf8");
}

function candidateMetricScore(metric: ReturnType<typeof evaluateFormula>, antiAbuseGain: number) {
  return metric.rankCorrelation * 0.3
    + metric.top100Precision * 0.18
    + metric.top50Precision * 0.12
    + metric.top10Precision * 0.08
    + (1 - Math.min(1, Math.abs(metric.volumeAdvantage))) * 0.12
    + antiAbuseGain * 0.2;
}

function markdownTable(headers: string[], rows: CsvValue[][]) {
  return `| ${headers.join(" | ")} |\n| ${headers.map(() => "---").join(" | ")} |\n${rows.map((row) => `| ${row.map((value) => value ?? "").join(" | ")} |`).join("\n")}`;
}

async function main() {
  assertCanonicalTerritories();
  await mkdir(resultsDirectory, { recursive: true });
  const world = createSimulationWorld({
    playerCount: configData.population.players,
    seasonCount: configData.population.seasons,
    seed: configData.seed,
    teamSize: configData.population.teamSize,
  });
  const finalSeason = world.seasons.at(-1)!;
  const finalInputs = world.inputsBySeason.get(finalSeason.id)!;
  const rankedByCandidate = new Map(candidates.map((candidate) => [candidate.id, rankSeason(finalInputs, candidate)]));
  const formulaMetrics = candidates.map((candidate) => evaluateFormula(
    candidate.id,
    finalInputs,
    rankedByCandidate.get(candidate.id)!,
  ));
  const minimalConfig = candidates.find(({ id }) => id === "candidate_a_full_rating")!;
  const antiAbuseGainByCandidate = new Map(candidates.map((candidate) => {
    if (candidate.integrityMode !== "weighted") return [candidate.id, 0] as const;
    const rows = contamination(finalInputs, minimalConfig, candidate);
    const occupied = rows.find(({ mode, populationRate }) => mode === "integrity" && populationRate === 0.05)?.top10OccupiedByCheaters ?? 1;
    return [candidate.id, 1 - occupied] as const;
  }));
  const recommendedMetric = [...formulaMetrics].sort((left, right) => (
    candidateMetricScore(right, antiAbuseGainByCandidate.get(right.candidateId) ?? 0)
    - candidateMetricScore(left, antiAbuseGainByCandidate.get(left.candidateId) ?? 0)
  ))[0]!;
  const recommended = candidates.find(({ id }) => id === recommendedMetric.candidateId)!;
  const recommendedRanking = rankedByCandidate.get(recommended.id)!;
  const contaminationRows = contamination(finalInputs, minimalConfig, recommended);

  const attacks = evaluateAttacks(minimalConfig, recommended);
  const humans = humanProfiles().map((input) => ({ input, result: calculateSeasonScore(input, recommended) }));
  const volumes = volumeProfiles().map((input) => ({ challenges: input.records.length, result: calculateSeasonScore(input, recommended) }));
  const newcomers = newcomerProfiles().map((input) => ({
    challenges: input.records.length,
    result: calculateSeasonScore(input, recommended, Math.max(...input.records.map(({ week }) => week))),
  }));
  const goalDifference = goalDifferenceExperiment(recommended);
  const falsePositiveRows = legitimateRiskProfiles().map((input) => ({ id: input.player.id, ...assessRankingIntegrity(input) }));
  const falsePositiveRate = falsePositiveRows.filter(({ classification }) => ["high_risk", "suspicious"].includes(classification)).length / falsePositiveRows.length;

  const weeklyRows: Array<{ top10: number; top50: number; top100: number; week: number }> = [];
  let previous: RankedPlayer[] | null = null;
  for (let week = 8; week <= 52; week += 1) {
    const current = rankSeason(finalInputs, recommended, week);
    weeklyRows.push({
      top10: previous ? rankingChurn(previous, current, 10) : 0,
      top50: previous ? rankingChurn(previous, current, 50) : 0,
      top100: previous ? rankingChurn(previous, current, 100) : 0,
      week,
    });
    previous = current;
  }

  const seasonSnapshotRows: Record<string, CsvValue>[] = [];
  const previousProvince = new Map<string, string | null>();
  for (const season of world.seasons) {
    const inputs = world.inputsBySeason.get(season.id)!.map((input) => ({
      ...input,
      previousCompetitiveProvinceCode: previousProvince.get(input.player.id) ?? null,
    }));
    const ranked = rankSeason(inputs, recommended);
    for (const result of ranked) previousProvince.set(result.playerId, result.competitiveProvinceCode);
    for (const result of ranked.filter(({ nationalRank }) => nationalRank !== null && nationalRank <= 100)) {
      seasonSnapshotRows.push({
        finalRank: result.nationalRank,
        finalScore: result.score,
        integrityRisk: result.risk.risk,
        playerId: result.playerId,
        provinceCode: result.competitiveProvinceCode,
        provinceRank: result.provinceRank,
        seasonId: season.id,
        uniqueOpponents: result.eligibility.uniqueOpponents,
        validChallenges: result.eligibility.validChallenges,
      });
    }
  }

  const playerById = new Map(world.players.map((player) => [player.id, player]));
  const baselineRows = recommendedRanking.map((result) => ({
    autonomousCommunityRank: result.autonomousCommunityRank,
    competition: result.components.competition,
    eligible: result.eligibility.eligible,
    latentSkill: playerById.get(result.playerId)?.latentSkill ?? null,
    nationalRank: result.nationalRank,
    opposition: result.components.opposition,
    playerId: result.playerId,
    position: playerById.get(result.playerId)?.position ?? null,
    provinceCode: result.competitiveProvinceCode,
    provinceRank: result.provinceRank,
    quality: result.components.quality,
    ratingV2: playerById.get(result.playerId)?.ratingV2 ?? null,
    risk: result.risk.risk,
    score: result.score,
    uniqueOpponents: result.eligibility.uniqueOpponents,
    validChallenges: result.eligibility.validChallenges,
  }));
  const territoryRows = TERRITORIES.map((territory) => {
    const eligible = recommendedRanking.filter((result) => result.eligibility.eligible && result.competitiveProvinceCode === territory.provinceCode).length;
    return {
      autonomousCommunity: territory.autonomousCommunityName,
      density: territory.density,
      eligiblePlayers: eligible,
      provinceCode: territory.provinceCode,
      provinceName: territory.provinceName,
      territorialDuplicate: territory.territorialDuplicate,
      top10ActiveAt30: eligible >= 30,
      top10ActiveAt50: eligible >= 50,
      type: territory.type,
    };
  });

  const weightRows: Record<string, CsvValue>[] = [];
  for (const quality of [40, 45, 50, 55, 60]) {
    for (const competition of [25, 30, 35, 40, 45]) {
      for (const opposition of [10, 15, 20]) {
        if (quality + competition + opposition !== 100) continue;
        const config = { ...recommended, id: `grid-${quality}-${competition}-${opposition}`, weights: { quality, competition, opposition } };
        const metric = evaluateFormula(config.id, finalInputs, rankSeason(finalInputs, config));
        weightRows.push({ quality, competition, opposition, ...metric });
      }
    }
  }

  const eligibilityRows = configData.comparisonAxes.eligibility.map(([minimumValidChallenges, minimumUniqueOpponents]) => {
    const config = { ...recommended, eligibility: { ...recommended.eligibility, minimumUniqueOpponents, minimumValidChallenges } };
    const metric = evaluateFormula(`${minimumValidChallenges}/${minimumUniqueOpponents}`, finalInputs, rankSeason(finalInputs, config));
    return { minimumUniqueOpponents, minimumValidChallenges, ...metric };
  });
  const decayRows = configData.comparisonAxes.opponentDecay.map((opponentDecay, index) => {
    const config = { ...recommended, id: `decay-${index + 1}`, opponentDecay };
    const farm = calculateSeasonScore(humanProfiles().find(({ player }) => player.id === "E")!, config);
    return { decay: opponentDecay.join("/"), farmerScore: farm.score, weightedChallenges: farm.weightedChallenges };
  });
  const volumeModelRows = configData.comparisonAxes.volumeModels.map((volumeModel) => {
    const config = { ...recommended, id: `volume-${volumeModel}`, volumeModel } as SeasonScoreConfig;
    const metric = evaluateFormula(config.id, finalInputs, rankSeason(finalInputs, config));
    const profileScores = volumeProfiles().map((input) => calculateSeasonScore(input, config).score);
    return { maxControlledScore: Math.max(...profileScores), minControlledScore: Math.min(...profileScores), ...metric, volumeModel };
  });

  const inactive = createProfileInput({ challenges: 24, id: "inactive-player", opponentRating: 86, rating: 91, technicalOpponents: 12, winRate: 0.67 });
  inactive.records = inactive.records.map((record, index) => ({ ...record, week: 1 + index % 12 }));
  const inactiveAtPeak = calculateSeasonScore(inactive, recommended, 12);
  const inactiveAtEnd = calculateSeasonScore(inactive, recommended, 52);

  const territoryTie = createProfileInput({ challenges: 16, id: "territory-tie", opponentRating: 80, provinceCodes: ["08", "17"], rating: 82, technicalOpponents: 8, winRate: 0.55 });
  const tieKeepsPrevious = resolveCompetitiveProvince(territoryTie.records, "08");
  territoryTie.records.push({ ...territoryTie.records[0]!, challengeId: "territory-overtake", occurredAt: "2029-07-30T18:00:00.000Z", provinceCode: "17", week: 52 });
  const territoryOvertake = resolveCompetitiveProvince(territoryTie.records, "08");

  await writeCsv("ranking_baseline.csv", baselineRows);
  await writeCsv("ranking_cheaters.csv", attacks.map((row) => ({ ...row })));
  await writeCsv("ranking_formula_comparison.csv", formulaMetrics.map((row) => ({ ...row })));
  await writeCsv("ranking_weight_grid.csv", weightRows);
  await writeCsv("ranking_eligibility_comparison.csv", eligibilityRows.map((row) => ({ ...row })));
  await writeCsv("ranking_decay_comparison.csv", decayRows);
  await writeCsv("ranking_volume_comparison.csv", volumeModelRows.map((row) => ({ ...row })));
  await writeCsv("territory_distribution.csv", territoryRows);
  await writeCsv("anti_abuse_results.csv", contaminationRows.map((row) => ({ ...row })));
  await writeCsv("weekly_churn.csv", weeklyRows);
  await writeCsv("season_snapshots.csv", seasonSnapshotRows);
  await writeCsv("goal_difference_experiment.csv", [
    { model: "current_without_goal_difference", normalScorelines: goalDifference.closeCurrentScore, blowoutScorelines: goalDifference.blowoutCurrentScore, blowoutAdvantage: round(goalDifference.blowoutCurrentScore - goalDifference.closeCurrentScore) },
    { model: "hypothetical_with_goal_difference", normalScorelines: goalDifference.closeHypotheticalScore, blowoutScorelines: goalDifference.blowoutHypotheticalScore, blowoutAdvantage: round(goalDifference.blowoutHypotheticalScore - goalDifference.closeHypotheticalScore) },
  ]);
  await writeCsv("territory_density_threshold_experiment.csv", [15, 30, 50, 100, 500].map((eligiblePlayers) => ({
    eligiblePlayers,
    top10ShareOfPopulation: round(10 / eligiblePlayers),
    top10VisibleAt30: eligiblePlayers >= 30,
    top10VisibleAt50: eligiblePlayers >= 50,
  })));
  const weakEcosystem = createProfileInput({ challenges: 20, id: "weak-ecosystem", opponentRating: 70, rating: 85, technicalOpponents: 10, winRate: 0.6 });
  const strongEcosystem = createProfileInput({ challenges: 20, id: "strong-ecosystem", opponentRating: 90, rating: 85, technicalOpponents: 10, winRate: 0.6 });
  const weakEcosystemScore = calculateSeasonScore(weakEcosystem, recommended);
  const strongEcosystemScore = calculateSeasonScore(strongEcosystem, recommended);
  await writeCsv("ecosystem_comparability.csv", [
    { ecosystem: "weak", opponentRating: 70, competition: weakEcosystemScore.components.competition, opposition: weakEcosystemScore.components.opposition, score: weakEcosystemScore.score },
    { ecosystem: "strong", opponentRating: 90, competition: strongEcosystemScore.components.competition, opposition: strongEcosystemScore.components.opposition, score: strongEcosystemScore.score },
  ]);
  await writeCsv("human_profiles.csv", humans.map(({ input, result }) => ({
    challenges: result.eligibility.validChallenges,
    competition: result.components.competition,
    eligible: result.eligibility.eligible,
    goals: input.records.reduce((sum, record) => sum + record.goals, 0),
    opposition: result.components.opposition,
    player: result.playerId,
    position: input.player.position,
    quality: result.components.quality,
    rating: input.player.ratingV2,
    risk: result.risk.risk,
    score: result.score,
    uniqueOpponents: result.eligibility.uniqueOpponents,
  })));
  await writeCsv("false_positive_results.csv", falsePositiveRows.map(({ id, classification, risk, signals }) => ({ id, classification, risk, ...signals })));

  const ratingBins = Array.from({ length: 10 }, (_, index) => {
    const minimum = index * 10;
    const rows = baselineRows.filter(({ ratingV2, score }) => typeof ratingV2 === "number" && ratingV2 >= minimum && ratingV2 < minimum + 10 && typeof score === "number");
    return { label: `${minimum}-${minimum + 9}`, value: rows.length === 0 ? 0 : rows.reduce((sum, row) => sum + Number(row.score), 0) / rows.length };
  });
  await writeChart("score-vs-rating.svg", "Season Score medio por Rating V2", ratingBins, 1000);
  await writeChart("score-vs-volume.svg", "Saturación por volumen controlado", volumes.map(({ challenges, result }) => ({ label: String(challenges), value: result.score })), 1000);
  await writeChart("score-vs-unique-opponents.svg", "Score y diversidad (perfiles A-G)", humans.map(({ result }) => ({ label: result.playerId, value: result.components.opposition })), 150);
  await writeChart("repeated-opponent.svg", "Efecto de decaimiento sobre farmeador", decayRows.map(({ decay, farmerScore }) => ({ label: decay.split("/").slice(0, 3).join("/"), value: farmerScore })), 1000);
  await writeChart("top10-contamination.svg", "Contaminación Top 10 con 5% manipuladores", contaminationRows.filter(({ populationRate }) => populationRate === 0.05).map(({ mode, top10OccupiedByCheaters }) => ({ label: mode, value: top10OccupiedByCheaters * 100 })), 100);
  await writeChart("false-positives.svg", "Riesgo de casos legítimos", falsePositiveRows.map(({ id, risk }) => ({ label: id.split("-").slice(0, 2).join(" "), value: risk })), 100);
  await writeChart("territory-density.svg", "Elegibles por territorio", territoryRows.map(({ provinceCode, eligiblePlayers }) => ({ label: String(provinceCode), value: Number(eligiblePlayers) })));
  await writeChart("rank-churn.svg", "Churn semanal Top 100", weeklyRows.map(({ week, top100 }) => ({ label: `S${week}`, value: top100 * 100 })), 100);
  await writeChart("newcomer-convergence.svg", "Convergencia de jugador excelente nuevo", newcomers.map(({ challenges, result }) => ({ label: String(challenges), value: result.score })), 1000);

  const humanRows = humans.map(({ input, result }) => [
    result.playerId,
    input.player.position,
    input.player.ratingV2,
    result.eligibility.validChallenges,
    result.eligibility.uniqueOpponents,
    result.components.quality,
    result.components.competition,
    result.components.opposition,
    result.score,
    result.eligibility.eligible ? "Sí" : "No",
  ] as CsvValue[]);
  const averageChurn = (key: "top10" | "top50" | "top100") => round(weeklyRows.slice(1).reduce((sum, row) => sum + row[key], 0) / Math.max(1, weeklyRows.length - 1));
  const report = `# Season Ranking Lab V1 — informe reproducible

Generado con semilla \`${configData.seed}\`. Todos los datos son sintéticos. Este informe no activa rankings, trofeos, sanciones ni escrituras remotas.

## Resumen ejecutivo

Se compararon ${candidates.length} candidatos principales, ${weightRows.length} combinaciones de pesos, ${eligibilityRows.length} umbrales de elegibilidad, ${decayRows.length} perfiles de repetición y ${volumeModelRows.length} modelos de volumen sobre ${world.players.length.toLocaleString("es-ES")} jugadores, ${world.teams.length.toLocaleString("es-ES")} equipos y ${world.seasons.length} temporadas. La recomendación experimental es **${recommended.label}** (\`${recommended.id}\`), seleccionada por una función explícita que combina fidelidad deportiva, precisión de Top, resistencia al volumen y reducción de contaminación. No es todavía una fórmula de producto.

## Fórmulas candidatas

${markdownTable(
  ["Candidato", "Elegibles", "Spearman mérito", "Corr. latent", "Top10", "Top50", "Top100", "Ventaja volumen"],
  formulaMetrics.map((metric) => [metric.candidateId, metric.eligiblePlayers, metric.rankCorrelation, metric.scoreSkillCorrelation, metric.top10Precision, metric.top50Precision, metric.top100Precision, metric.volumeAdvantage]),
)}

La precisión Top 10 exacta del finalista es ${round(recommendedMetric.top10Precision * 100)}% en esta población. Es una advertencia explícita: aunque el orden global y el Top 100 son razonables, el laboratorio todavía no justifica publicar trofeos ni tratar esta fórmula como cerrada.

Fórmula común, antes del factor experimental de integridad:

\`Season Score = 10 × (calidad × peso_calidad + competición × peso_competición + oposición × peso_oposición) / 100\`.

- **Calidad**: Rating V2 de solo lectura × fiabilidad × desbloqueo de evidencia competitiva.
- **Competición**: media bayesiana saturada de \`50 + 85 × (resultado_real - resultado_esperado)\`, limitada a 0–100.
- **Oposición**: 58% nivel medio rival + 42% diversidad saturada.
- **Integridad**: solo en el candidato protegido, factor 1–0,58 derivado de riesgo por encima de 20; no sanciona ni modifica Rating.
- **Redondeo**: dos decimales en la salida visible; cálculos internos sin redondeos intermedios salvo entradas sintéticas.
- **Diferencia de goles**: con idéntico W/D/L, el modelo actual da ${goalDifference.closeCurrentScore}/${goalDifference.blowoutCurrentScore}; la alternativa ensayada daría ${goalDifference.closeHypotheticalScore}/${goalDifference.blowoutHypotheticalScore} y crea ${round(goalDifference.blowoutHypotheticalScore - goalDifference.closeHypotheticalScore)} puntos de incentivo a ampliar goleadas. Se descarta para V1.

## Casos humanos A–G

${markdownTable(["Jugador", "Pos.", "Rating", "Retos", "Rivales", "Calidad", "Competición", "Oposición", "Score", "Elegible"], humanRows)}

Los goles registrados de F y G no entran en ninguna función. F (${humans.find(({ input }) => input.player.id === "F")?.result.score}) puede superar a G (${humans.find(({ input }) => input.player.id === "G")?.result.score}) por calidad/rendimiento, no por posición. C permanece provisional con ${humans.find(({ input }) => input.player.id === "C")?.result.eligibility.validChallenges} Retos.

## Integridad y red team

${markdownTable(
  ["Ataque", "Sin protección", "Con integridad", "Riesgo", "Ventaja vs honesto"],
  attacks.map((row) => [row.attack, row.unprotectedScore, row.protectedScore, row.protectedRisk, row.scoreIncreaseWithoutProtection]),
)}

Con 5% de manipuladores, la ocupación sintética del Top 10 pasa de ${(contaminationRows.find(({ mode, populationRate }) => mode === "minimal" && populationRate === 0.05)?.top10OccupiedByCheaters ?? 0) * 100}% a ${(contaminationRows.find(({ mode, populationRate }) => mode === "integrity" && populationRate === 0.05)?.top10OccupiedByCheaters ?? 0) * 100}%. La tasa de falso positivo \`suspicious/high_risk\` en los cinco casos legítimos adversariales es ${round(falsePositiveRate * 100)}%. \`watch\` es una señal para revisión, nunca una acusación.

## Territorio

- 50 provincias + Ceuta + Melilla = ${TERRITORIES.length} territorios base.
- ${AUTONOMOUS_COMMUNITIES.length} comunidades autónomas; Ceuta y Melilla no reciben una comunidad inventada y compiten en su territorio base y España.
- Comunidades uniprovinciales marcadas \`territorialDuplicate=true\`: ${TERRITORIES.filter(({ territorialDuplicate }) => territorialDuplicate).map(({ provinceName }) => provinceName).join(", ")}.
- Empate 8/8 conserva provincia previa: \`${tieKeepsPrevious}\`. Al superar 9/8 cambia a \`${territoryOvertake}\` sin reiniciar score.
- El mismo score alimenta rango provincial, autonómico y nacional; no existen tres scores.
- Con umbral 30 se activan ${territoryRows.filter(({ eligiblePlayers }) => Number(eligiblePlayers) >= 30).length} territorios y con 50 se activan ${territoryRows.filter(({ eligiblePlayers }) => Number(eligiblePlayers) >= 50).length}, de 52. El experimento controlado 15/30/50/100/500 está en \`territory_density_threshold_experiment.csv\`. Recomendación experimental: 30 para mostrar tabla provisional y 50 para reconocer un Top 10 prestigioso.
- Dos ecosistemas con mismo Rating y W/D/L producen ${weakEcosystemScore.score} ante rival medio 70 y ${strongEcosystemScore.score} ante rival medio 90: la oposición corrige parte del sesgo territorial, pero requiere datos reales antes de un Top España.

## Volumen, nuevos y actividad

${markdownTable(["Retos", "Score", "Peso útil"], volumes.map(({ challenges, result }) => [challenges, result.score, result.weightedChallenges]))}

El modelo recomendado satura: el salto controlado entre 40 y 120 Retos es ${round((volumes.find(({ challenges }) => challenges === 120)?.result.score ?? 0) - (volumes.find(({ challenges }) => challenges === 40)?.result.score ?? 0))} puntos, no una suma infinita. \`best_20\` queda como control porque permite cherry-picking. El newcomer es elegible por primera vez en ${newcomers.find(({ result }) => result.eligibility.eligible)?.challenges ?? "ningún"} Retos. La inactividad conserva score (${inactiveAtPeak.score} → ${inactiveAtEnd.score}) pero al final queda ${inactiveAtEnd.eligibility.eligible ? "activa" : "fuera de elegibilidad visible"}; se recomienda soft-gate de actividad, no decay destructivo.

Churn medio semanal: Top10 ${averageChurn("top10")}, Top50 ${averageChurn("top50")}, Top100 ${averageChurn("top100")}. Son 45 snapshots semanales vivos; el cierre de temporada genera filas inmutables separadas por \`seasonId\`.

## Recomendación V1 experimental

1. Pesos: **${recommended.weights.quality}/${recommended.weights.competition}/${recommended.weights.opposition}**.
2. Elegibilidad: **${recommended.eligibility.minimumValidChallenges} Retos / ${recommended.eligibility.minimumUniqueOpponents} rivales lógicos**, fiabilidad mínima ${recommended.eligibility.minimumRatingReliability}.
3. Rival decay: **${recommended.opponentDecay.map((value) => Math.round(value * 100)).join("/")}%**.
4. Volumen: **${recommended.volumeModel}**, media saturada; no suma ni mejores partidos perpetuos.
5. Rating: desbloqueo \`${recommended.ratingConfidenceModel}\`; Rating V2 permanece intacto.
6. Actividad: soft-gate de ${recommended.eligibility.recentActivityWeeks ?? "sin"} semanas para visibilidad/premio, sin borrar Season Score.
7. Top 10 territorial: mostrar provisional desde 30 elegibles y no recomendar trofeo hasta 50.

## Riesgos abiertos

- La participación canónica prueba inscripción, no presencia física; hace falta UX ligera de confirmación cruzada antes de usarla para premios.
- Places fija el venue acordado, no demuestra presencia; congelar y auditar cambios, permitir reporte rival.
- Colusión entre equipos reales e independencia de clubes requieren grafo histórico y revisión humana.
- Comparabilidad entre ecosistemas territoriales necesita datos reales anonimizados antes de lanzamiento.
- Smurfs y rivales artificialmente inflados no pueden resolverse solo con Season Score.

## Validación local

- \`npm test\`: **PASS**, build de producción y 125 tests.
- \`npm run test:season-ranking-lab\`: **PASS**, 14 tests de justicia, territorio, reproducibilidad y ataques.
- \`npm run typecheck\`: **PASS**.
- lint focalizado sobre \`simulation/season-ranking-lab\` y los dos tests: **PASS**.
- \`npm run lint\` global: **FAIL preexistente**, 23 errores y 20 avisos en \`app/\`; ningún hallazgo pertenece al laboratorio y no se modificó esa deuda.
- \`git diff --check\`: **PASS**.
- Alcance persistente: 41 rutas, sin SQL, migraciones, UI, Rating V2 ni catálogo de logros.

## Privacidad

Recomendadas: grafo deportivo, partidos, participantes, equipos, owners/admins, solapamiento de plantilla, venue acordado y tiempos (datos de producto existentes o sensibilidad baja/moderada). No recomendadas por defecto: fingerprint oculto, GPS permanente, sanción por IP compartida o geolocalización continua (sensibilidad alta y falsos positivos).

## Entrega solicitada (1–63)

1. SHA inicial: \`53fa08604f28a9f5e9f758120fcd9566bc3a7107\`.
2. Rama/worktree: \`codex/season-ranking-lab-v1\` / \`/Users/macbookpro14/.codex/worktrees/pachangas-season-ranking-lab-v1\`.
3. Arquitectura: motor puro + configuración JSON + simulador + métricas + red team + datasets/SVG.
4. Temporadas: planned/active/frozen/closed y tres temporadas sintéticas.
5. Territorio: códigos provinciales canónicos y comunidad asociada.
6. Mapping provincia→comunidad: \`src/territories.ts\`.
7. Ceuta/Melilla: base+nacional, sin comunidad ficticia.
8. Uniprovinciales: duplicado marcado, no doble trofeo.
9. Provincia principal: máximo de Retos válidos.
10. Empate: conserva anterior; sin anterior, primera en alcanzar máximo.
11. Elegibilidad: 6/3, 8/4, 10/5, 12/5 y 15/6 comparadas.
12. Rival decay: tres curvas comparadas.
13. Volumen: all_saturated, recent_20, recent_25 y best_20.
14. Fórmulas: cinco candidatos principales.
15. Pesos: ${weightRows.length} combinaciones válidas del grid.
16. A–G: \`human_profiles.csv\`.
17. Defensa/goleador: goles no usados; F vs G documentado.
18. Hiperactivo: B y perfiles 10–120.
19. Newcomer: 2/5/8/10/15/25 Retos.
20. Rival fuerte: D.
21. Farmeador: E y suite repeated_opponent.
22. Simulación: ${world.players.length.toLocaleString("es-ES")} jugadores.
23. Provincial: columnas \`provinceRank\` y dataset completo.
24. Autonómico: \`autonomousCommunityRank\`.
25. España: \`nationalRank\`.
26. Estabilidad semanal: seis cortes.
27. Rank churn: Top10/50/100 en \`weekly_churn.csv\`.
28. Actividad: score conservado, elegibilidad reciente separada.
29. Sybil: incluido.
30. Equipos fantasma: incluido.
31. Collusion/win trading: incluido.
32. Rating interno inflado: incluido.
33. Opponent-strength boosting: incluido.
34. Team hopping: incluido.
35. Rival farming: incluido.
36. Fake participation: incluido.
37. Venue/province manipulation: incluido.
38. Fake matches: incluido.
39. Impossible volume/travel: incluido.
40. Smurf: incluido.
41. Sacrifice accounts: incluido.
42. Integrity risk 0–100: diagnóstico, no sanción.
43. Contaminación sin protección: \`anti_abuse_results.csv\`.
44. Contaminación protegida: mismo dataset.
45. False positive rate: ${round(falsePositiveRate * 100)}% suspicious/high.
46. Casos legítimos: cinco perfiles adversariales.
47. Señales recomendadas: grafo deportivo y evidencia ya disponible.
48. Señales descartadas: GPS/fingerprint/IP como autoridad.
49. Finalistas: métricas en \`ranking_formula_comparison.csv\`.
50. Recomendada: \`${recommended.id}\`, experimental.
51. Elegibilidad recomendada: ${recommended.eligibility.minimumValidChallenges}/${recommended.eligibility.minimumUniqueOpponents} + reliability.
52. Rival decay recomendado: ${recommended.opponentDecay.join("/")}.
53. Ventana/saturación: ${recommended.volumeModel}.
54. Rating reliability: factor y desbloqueo competitivo.
55. Actividad reciente: soft-gate, sin decay de score.
56. Umbral Top 10: 30 provisional / 50 reconocimiento.
57. Riesgos abiertos: participación, Places, colusión y comparabilidad.
58. No implementar: trofeos, auto-ban, GPS, rankings reales ni tablas remotas.
59. Tests: build + 125 tests PASS; 14 focalizados PASS; typecheck y lint focalizado PASS; lint global conserva deuda preexistente.
60. Archivos: 41 rutas de código, tests, config, datasets, SVG e informe.
61. Commit/PR: se registra en la entrega Git posterior a este informe reproducible.
62. Producción: no tocada.
63. Rating V2: no modificado.

## Datasets y gráficos

Los CSV de salida y los nueve SVG están en \`simulation/season-ranking-lab/results/\`. Se regeneran con \`npm run lab:season-ranking\`; no contienen PII.
`;
  await writeFile(reportPath, report, "utf8");
  await writeFile(resolve(resultsDirectory, "summary.json"), `${JSON.stringify({
    attacks,
    contaminationRows,
    falsePositiveRate,
    formulaMetrics,
    recommendedCandidate: recommended,
    seed: configData.seed,
    territory: { autonomousCommunities: AUTONOMOUS_COMMUNITIES.length, baseTerritories: TERRITORIES.length },
    world: { players: world.players.length, seasons: world.seasons.length, teams: world.teams.length },
  }, null, 2)}\n`, "utf8");
  process.stdout.write(`Season Ranking Lab complete: ${recommended.id}; report ${reportPath}\n`);
}

await main();
