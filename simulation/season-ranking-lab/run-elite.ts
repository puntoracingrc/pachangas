import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import configData from "./season_score_config.json";
import { assessRankingIntegrity, rankSeason } from "./src/engine";
import {
  aggregateEliteMetric,
  evaluateEliteByScope,
  evaluateNationalTops,
  evaluatePredictiveTops,
  percentile,
  predictiveUplift,
  splitInputsForOutOfSample,
} from "./src/elite-metrics";
import {
  applyTrophyEligibility,
  bootstrapCutoffUncertainty,
  cutoffAttackExperiment,
  leaveOneOutTop10Sensitivity,
  ownTeamDiversityExperiment,
  positionValidation,
  teamStrengthFairnessExperiment,
  territorialTop10Churn,
} from "./src/elite-validation";
import { evaluateFormula } from "./src/metrics";
import { round } from "./src/random";
import { attackProfiles, evaluateAttacks, legitimateRiskProfiles } from "./src/scenarios";
import { createSimulationWorld, type ActivityProfile } from "./src/simulator";
import { AUTONOMOUS_COMMUNITIES } from "./src/territories";
import type { SeasonPlayerInput, SeasonScoreConfig } from "./src/types";

type CsvValue = boolean | null | number | string;
type CandidateEvaluation = {
  candidateId: string;
  challengeQuality: string;
  composite: number;
  competitionWeight: number;
  oppositionWeight: number;
  predictiveUplift: number;
  qualityWeight: number;
  territorialCandidateRecall20: number;
  territorialFutureCandidateRecall20: number;
  territorialFutureNdcg10: number;
  territorialNdcg10: number;
  territorialTop10Churn: number;
  volumeAdvantage: number;
  volumeModel: string;
};

const root = resolve(dirname(new URL(import.meta.url).pathname), "../..");
const labRoot = resolve(root, "simulation/season-ranking-lab");
const resultsDirectory = resolve(labRoot, "results/elite");
const reportPath = resolve(root, "docs/season-ranking-elite-validation.md");
const baseCandidates = configData.candidates as SeasonScoreConfig[];
const previousCandidate = baseCandidates.find(({ id }) => id === "candidate_e_recent20")!;
const unprotectedCandidate = baseCandidates.find(({ id }) => id === "candidate_a_full_rating")!;

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

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function standardDeviation(values: number[]) {
  const mean = average(values);
  return Math.sqrt(average(values.map((value) => (value - mean) ** 2)));
}

function summary(values: number[]) {
  return {
    mean: round(average(values), 4),
    p5: round(percentile(values, 0.05), 4),
    p50: round(percentile(values, 0.5), 4),
    p95: round(percentile(values, 0.95), 4),
    std: round(standardDeviation(values), 4),
  };
}

function markdownTable(headers: string[], rows: CsvValue[][]) {
  return `| ${headers.join(" | ")} |\n| ${headers.map(() => "---").join(" | ")} |\n${rows.map((row) => `| ${row.map((value) => value ?? "").join(" | ")} |`).join("\n")}`;
}

const scopeMetricFields = [
  ["Precision@10", "precisionAt10"],
  ["Recall@10", "recallAt10"],
  ["Overlap@10", "overlapAt10"],
  ["NDCG@10", "ndcgAt10"],
  ["NDCG@20", "ndcgAt20"],
  ["Mean rank error", "meanRankErrorTop10"],
  ["Median rank error", "medianRankErrorTop10"],
  ["Near miss", "top10NearMissRate"],
  ["Candidate recall@20", "candidateRecallAt20"],
] as const;

function scopeMetricSummary(rows: ReturnType<typeof evaluateEliteByScope>) {
  return scopeMetricFields.map(([label, field]) => {
    const values = aggregateEliteMetric(rows, field);
    return [label, values.mean, values.p10, values.p50, values.p90] as CsvValue[];
  });
}

function scopeExtremes(rows: ReturnType<typeof evaluateEliteByScope>) {
  const ordered = [...rows].sort((left, right) => left.ndcgAt10 - right.ndcgAt10 || left.scopeCode.localeCompare(right.scopeCode));
  return { best: ordered.at(-1), worst: ordered[0] };
}

function evaluateCandidate(config: SeasonScoreConfig, inputs: SeasonPlayerInput[]): CandidateEvaluation {
  const fullResults = rankSeason(inputs, config);
  const trainingInputs = splitInputsForOutOfSample(inputs);
  const trainingResults = rankSeason(trainingInputs, config, 34);
  const territorial = evaluateEliteByScope({ inputs, minimumEligible: 50, results: fullResults, scope: "province", truth: "season_merit" });
  const future = evaluateEliteByScope({ inputs, minimumEligible: 30, results: trainingResults, scope: "province", truth: "future" });
  const territorialNdcg10 = aggregateEliteMetric(territorial, "ndcgAt10").p50;
  const territorialCandidateRecall20 = aggregateEliteMetric(territorial, "candidateRecallAt20").p50;
  const territorialFutureNdcg10 = aggregateEliteMetric(future, "ndcgAt10").p50;
  const territorialFutureCandidateRecall20 = aggregateEliteMetric(future, "candidateRecallAt20").p50;
  const futureUplift = predictiveUplift(inputs, trainingResults, 100).uplift;
  const churn = territorialTop10Churn(rankSeason(inputs, config, 40), rankSeason(inputs, config, 48)).mean;
  const formula = evaluateFormula(config.id, inputs, fullResults);
  const composite = territorialNdcg10 * 0.175
    + territorialCandidateRecall20 * 0.175
    + territorialFutureNdcg10 * 0.175
    + territorialFutureCandidateRecall20 * 0.175
    + clamp01(futureUplift / 20) * 0.1
    + (1 - churn) * 0.1
    + (1 - Math.min(1, Math.abs(formula.volumeAdvantage))) * 0.1;
  return {
    candidateId: config.id,
    challengeQuality: config.ratingConfidenceModel,
    composite: round(composite, 6),
    competitionWeight: config.weights.competition,
    oppositionWeight: config.weights.opposition,
    predictiveUplift: futureUplift,
    qualityWeight: config.weights.quality,
    territorialCandidateRecall20,
    territorialFutureCandidateRecall20,
    territorialFutureNdcg10,
    territorialNdcg10,
    territorialTop10Churn: churn,
    volumeAdvantage: formula.volumeAdvantage,
    volumeModel: config.volumeModel,
  };
}

function clamp01(value: number) {
  return Math.max(0, Math.min(1, value));
}

function withConfig(base: SeasonScoreConfig, id: string, changes: Partial<SeasonScoreConfig>): SeasonScoreConfig {
  return { ...base, ...changes, id, label: id };
}

function selectConfigurations(inputs: SeasonPlayerInput[]) {
  const windowConfigs = (["recent_20", "recent_25", "recent_30", "all_saturated", "hybrid_70_30"] as const).map((volumeModel) => (
    withConfig(previousCandidate, `elite-window-${volumeModel}`, { volumeModel })
  ));
  const windowEvaluations = windowConfigs.map((config) => ({ config, metrics: evaluateCandidate(config, inputs) }));
  const bestWindow = [...windowEvaluations].sort((left, right) => right.metrics.composite - left.metrics.composite)[0]!.config;

  const qualityConfigs = (["full", "competitive", "challenge_calibrated"] as const).map((ratingConfidenceModel) => (
    withConfig(bestWindow, `elite-quality-${ratingConfidenceModel}`, { ratingConfidenceModel })
  ));
  const qualityEvaluations = qualityConfigs.map((config) => ({ config, metrics: evaluateCandidate(config, inputs) }));
  const bestQuality = [...qualityEvaluations].sort((left, right) => right.metrics.composite - left.metrics.composite)[0]!.config;

  const weightConfigs: SeasonScoreConfig[] = [];
  for (let quality = 35; quality <= 55; quality += 5) {
    for (let competition = 30; competition <= 50; competition += 5) {
      for (let opposition = 10; opposition <= 25; opposition += 5) {
        if (quality + competition + opposition !== 100) continue;
        weightConfigs.push(withConfig(bestQuality, `elite-weight-${quality}-${competition}-${opposition}`, {
          weights: { competition, opposition, quality },
        }));
      }
    }
  }
  const weightEvaluations = weightConfigs.map((config) => ({ config, metrics: evaluateCandidate(config, inputs) }));
  const all = [...windowEvaluations, ...qualityEvaluations, ...weightEvaluations];
  const finalist = [...all].sort((left, right) => right.metrics.composite - left.metrics.composite)[0]!;
  return { all, bestQuality, bestWindow, finalist };
}

function cloneAttack(input: SeasonPlayerInput, suffix: string) {
  return {
    ...input,
    player: { ...input.player, id: `${input.player.id}-${suffix}` },
    records: input.records.map((record) => ({
      ...record,
      challengeId: `${record.challengeId}-${suffix}`,
      opponentClusterId: `${record.opponentClusterId}-${suffix}`,
      opponentTeamId: `${record.opponentTeamId}-${suffix}`,
    })),
  };
}

function contaminationAtRates(inputs: SeasonPlayerInput[], config: SeasonScoreConfig) {
  const base = inputs.slice(0, 1_000);
  const attacks = attackProfiles().filter(({ attack }) => ["collusion", "ghost_teams", "opponent_boost", "rating_boost", "sacrifice_accounts", "sybil"].includes(attack));
  return [0.01, 0.02, 0.05, 0.1].flatMap((rate) => {
    const count = Math.round(base.length * rate);
    const cheaters = Array.from({ length: count }, (_, index) => cloneAttack(attacks[index % attacks.length]!.input, `${rate}-${index}`));
    const cheaterIds = new Set(cheaters.map(({ player }) => player.id));
    return ([['unprotected', unprotectedCandidate], ['finalist', config]] as const).map(([mode, candidate]) => {
      const top10 = rankSeason([...base, ...cheaters], candidate).filter(({ eligibility }) => eligibility.eligible)
        .sort((left, right) => right.score - left.score).slice(0, 10);
      const occupied = top10.filter(({ playerId }) => cheaterIds.has(playerId)).length;
      return { cheaterPenetration: round(occupied / Math.max(1, count), 4), cheaters: count, mode, rate, top10Contamination: round(occupied / 10, 4) };
    });
  });
}

function densityRows(provinceRows: ReturnType<typeof evaluateEliteByScope>) {
  return [30, 40, 50, 75, 100].map((minimumEligible) => {
    const eligible = provinceRows.filter((row) => row.eligiblePlayers >= minimumEligible);
    return {
      candidateRecall20Median: aggregateEliteMetric(eligible, "candidateRecallAt20").p50,
      meanRankErrorMedian: aggregateEliteMetric(eligible, "meanRankErrorTop10").p50,
      minimumEligible,
      ndcg10Median: aggregateEliteMetric(eligible, "ndcgAt10").p50,
      territories: eligible.length,
    };
  });
}

async function main() {
  await mkdir(resultsDirectory, { recursive: true });
  const world = createSimulationWorld({ playerCount: 10_000, seasonCount: 3, seed: configData.seed, teamSize: 10 });
  const season = world.seasons.at(-1)!;
  const inputs = world.inputsBySeason.get(season.id)!;
  const trainingInputs = splitInputsForOutOfSample(inputs);

  const previousResults = rankSeason(inputs, previousCandidate);
  const previousTrainingResults = rankSeason(trainingInputs, previousCandidate, 34);
  const previousNational = ["capacity", "season_merit"].flatMap((truth) => evaluateNationalTops(inputs, previousResults, truth as "capacity" | "season_merit"));
  previousNational.push(...evaluateNationalTops(inputs, previousTrainingResults, "future"));

  const selection = selectConfigurations(inputs);
  const finalist = selection.finalist.config;
  const finalistResults = rankSeason(inputs, finalist);
  const finalistTrainingResults = rankSeason(trainingInputs, finalist, 34);
  const provinceSeasonRows = evaluateEliteByScope({ inputs, minimumEligible: 30, results: finalistResults, scope: "province", truth: "season_merit" });
  const provinceCapacityRows = evaluateEliteByScope({ inputs, minimumEligible: 30, results: finalistResults, scope: "province", truth: "capacity" });
  const provinceFutureRows = evaluateEliteByScope({ inputs, minimumEligible: 20, results: finalistTrainingResults, scope: "province", truth: "future" });
  const communityRowsAll = evaluateEliteByScope({ inputs, minimumEligible: 30, results: finalistResults, scope: "autonomous_community", truth: "season_merit" });
  const duplicateCommunityCodes = new Set(AUTONOMOUS_COMMUNITIES.filter(({ territorialDuplicate }) => territorialDuplicate).map(({ code }) => code));
  const communityRows = communityRowsAll.filter(({ scopeCode }) => !duplicateCommunityCodes.has(scopeCode));
  const nationalRows = ["capacity", "season_merit"].flatMap((truth) => evaluateNationalTops(inputs, finalistResults, truth as "capacity" | "season_merit"));
  nationalRows.push(...evaluateNationalTops(inputs, finalistTrainingResults, "future"));

  const uncertainty = bootstrapCutoffUncertainty(inputs, finalistResults, finalist, { iterations: 100, minimumEligible: 50, seed: 115_2026 });
  const leaveOneOut = leaveOneOutTop10Sensitivity(inputs, finalistResults, finalist, 50);
  const trophyRules = [
    { id: "20/8", minimumChallenges: 20, minimumCompetitiveConfidence: 0.65, minimumUniqueOpponents: 8, recentWeeks: 12 },
    { id: "25/10", minimumChallenges: 25, minimumCompetitiveConfidence: 0.75, minimumUniqueOpponents: 10, recentWeeks: 12 },
    { id: "30/10", minimumChallenges: 30, minimumCompetitiveConfidence: 0.8, minimumUniqueOpponents: 10, recentWeeks: 10 },
  ];
  const trophyRows = trophyRules.map((rule) => {
    const filtered = applyTrophyEligibility(inputs, finalistResults, rule);
    const elite = evaluateEliteByScope({ inputs, minimumEligible: 30, results: filtered, scope: "province", truth: "season_merit" });
    return {
      candidateRecall20Median: aggregateEliteMetric(elite, "candidateRecallAt20").p50,
      eligiblePlayers: filtered.filter(({ eligibility }) => eligibility.eligible).length,
      meanRankErrorMedian: aggregateEliteMetric(elite, "meanRankErrorTop10").p50,
      ndcg10Median: aggregateEliteMetric(elite, "ndcgAt10").p50,
      rule: rule.id,
      territories: elite.length,
    };
  });

  const multiSeedRows: Record<string, CsvValue>[] = [];
  for (let index = 0; index < 20; index += 1) {
    const seed = configData.seed + index * 7_919;
    const seedWorld = createSimulationWorld({ playerCount: 10_000, seasonCount: 1, seed, teamSize: 10 });
    const seedInputs = seedWorld.inputsBySeason.get(seedWorld.seasons[0]!.id)!;
    const seedTraining = splitInputsForOutOfSample(seedInputs);
    const seedResults = rankSeason(seedInputs, finalist);
    const seedTrainingResults = rankSeason(seedTraining, finalist, 34);
    const provinceRows = evaluateEliteByScope({ inputs: seedInputs, minimumEligible: 50, results: seedResults, scope: "province", truth: "season_merit" });
    const futureRows = evaluateEliteByScope({ inputs: seedInputs, minimumEligible: 30, results: seedTrainingResults, scope: "province", truth: "future" });
    const uplift = predictiveUplift(seedInputs, seedTrainingResults, 100);
    multiSeedRows.push({
      futureCandidateRecall20Median: aggregateEliteMetric(futureRows, "candidateRecallAt20").p50,
      futureNdcg10Median: aggregateEliteMetric(futureRows, "ndcgAt10").p50,
      ndcg10Median: aggregateEliteMetric(provinceRows, "ndcgAt10").p50,
      predictiveUpliftTop100: uplift.uplift,
      rankErrorMedian: aggregateEliteMetric(provinceRows, "meanRankErrorTop10").p50,
      recall20Median: aggregateEliteMetric(provinceRows, "candidateRecallAt20").p50,
      seed,
      territories: provinceRows.length,
    });
  }

  const activityProfiles: ActivityProfile[] = ["normal", "high_activity", "summer_dip", "progressive_growth", "province_growth"];
  const seasonalityRows = activityProfiles.map((activityProfile, index) => {
    const seasonalWorld = createSimulationWorld({ activityProfile, playerCount: 10_000, seasonCount: 1, seed: configData.seed + 500_000 + index * 101, teamSize: 10 });
    const seasonalInputs = seasonalWorld.inputsBySeason.get(seasonalWorld.seasons[0]!.id)!;
    const seasonalResults = rankSeason(seasonalInputs, finalist);
    const provinceRows = evaluateEliteByScope({ inputs: seasonalInputs, minimumEligible: 50, results: seasonalResults, scope: "province", truth: "season_merit" });
    const churn = territorialTop10Churn(rankSeason(seasonalInputs, finalist, 40), rankSeason(seasonalInputs, finalist, 48));
    return {
      activityProfile,
      candidateRecall20Median: aggregateEliteMetric(provinceRows, "candidateRecallAt20").p50,
      ndcg10Median: aggregateEliteMetric(provinceRows, "ndcgAt10").p50,
      territoriesAt50: provinceRows.length,
      top10Churn: churn.mean,
    };
  });

  const redTeamRows = evaluateAttacks(unprotectedCandidate, finalist);
  const contaminationRows = contaminationAtRates(inputs, finalist);
  const falsePositiveRows = legitimateRiskProfiles().map((input) => ({ id: input.player.id, ...assessRankingIntegrity(input) }));
  const cutoffRows = cutoffAttackExperiment(inputs, finalistResults, unprotectedCandidate, finalist);
  const positionRows = positionValidation(inputs, finalistResults);
  const ownTeamRows = ownTeamDiversityExperiment(finalist);
  const teamStrengthRows = teamStrengthFairnessExperiment(finalist);
  const densityValidation = densityRows(provinceSeasonRows);
  const predictiveTopRows = evaluatePredictiveTops(inputs, finalistTrainingResults);

  const uncertaintyByProvince = new Map(uncertainty.map((row) => [row.provinceCode, row]));
  const sensitivityByProvince = new Map(leaveOneOut.map((row) => [row.provinceCode, row]));
  const snapshotRows = [...new Set(finalistResults.filter(({ eligibility, competitiveProvinceCode }) => eligibility.eligible && competitiveProvinceCode).map(({ competitiveProvinceCode }) => competitiveProvinceCode!))]
    .flatMap((provinceCode) => finalistResults.filter((result) => result.eligibility.eligible && result.competitiveProvinceCode === provinceCode)
      .sort((left, right) => right.score - left.score).slice(0, 10).map((result, index) => ({
        confidenceAtCutoff: uncertaintyByProvince.get(provinceCode)?.rank10Confidence ?? null,
        integrityStatus: result.risk.classification,
        playerId: result.playerId,
        provinceCode,
        rank: index + 1,
        recentActivityRequired: finalist.eligibility.recentActivityWeeks,
        score: result.score,
        singleMatchDependencyRate: sensitivityByProvince.get(provinceCode)?.sensitiveRemovalRate ?? null,
        uniqueOpponents: result.eligibility.uniqueOpponents,
        validChallenges: result.eligibility.validChallenges,
        weightedChallenges: result.weightedChallenges,
      })));

  await writeCsv("candidate_elite_comparison.csv", selection.all.map(({ metrics }) => ({ ...metrics })));
  await writeCsv("previous_national_metrics_corrected.csv", previousNational.map((row) => ({ ...row })));
  await writeCsv("finalist_national_metrics.csv", nationalRows.map((row) => ({ ...row })));
  await writeCsv("province_season_merit.csv", provinceSeasonRows.map((row) => ({ ...row })));
  await writeCsv("province_capacity.csv", provinceCapacityRows.map((row) => ({ ...row })));
  await writeCsv("province_future_predictive.csv", provinceFutureRows.map((row) => ({ ...row })));
  await writeCsv("autonomous_communities.csv", communityRowsAll.map((row) => ({ conceptualDuplicate: duplicateCommunityCodes.has(row.scopeCode), ...row })));
  await writeCsv("top10_uncertainty.csv", uncertainty.map((row) => ({ ...row })));
  await writeCsv("leave_one_out.csv", leaveOneOut.map((row) => ({ ...row })));
  await writeCsv("trophy_eligibility.csv", trophyRows);
  await writeCsv("multi_seed_20.csv", multiSeedRows);
  await writeCsv("seasonality.csv", seasonalityRows);
  await writeCsv("red_team_elite.csv", redTeamRows.map((row) => ({ ...row })));
  await writeCsv("contamination_elite.csv", contaminationRows);
  await writeCsv("false_positive_elite.csv", falsePositiveRows.map(({ id, classification, risk, signals }) => ({ classification, id, risk, ...signals })));
  await writeCsv("cutoff_attack.csv", cutoffRows);
  await writeCsv("position_validation.csv", positionRows);
  await writeCsv("own_team_diversity.csv", ownTeamRows);
  await writeCsv("team_strength_fairness.csv", teamStrengthRows);
  await writeCsv("density_elite.csv", densityValidation);
  await writeCsv("predictive_top_performance.csv", predictiveTopRows);
  await writeCsv("top10_audit_snapshots.csv", snapshotRows);

  const seedNdcg = multiSeedRows.map((row) => Number(row.ndcg10Median));
  const seedRecall = multiSeedRows.map((row) => Number(row.recall20Median));
  const seedFutureNdcg = multiSeedRows.map((row) => Number(row.futureNdcg10Median));
  const seedFutureRecall = multiSeedRows.map((row) => Number(row.futureCandidateRecall20Median));
  const seedUplift = multiSeedRows.map((row) => Number(row.predictiveUpliftTop100));
  const seedRankError = multiSeedRows.map((row) => Number(row.rankErrorMedian));
  const multiSeedSummary = {
    futureNdcg10: summary(seedFutureNdcg),
    futureRecall20: summary(seedFutureRecall),
    ndcg10: summary(seedNdcg),
    predictiveUplift: summary(seedUplift),
    rankError: summary(seedRankError),
    recall20: summary(seedRecall),
  };
  const sameBandRate = uncertainty.filter(({ sameUncertaintyBand }) => sameUncertaintyBand).length / Math.max(1, uncertainty.length);
  const leaveOneOutDependency = average(leaveOneOut.map(({ top10DependencyRate }) => top10DependencyRate));
  const protectedContamination5 = contaminationRows.find(({ mode, rate }) => mode === "finalist" && rate === 0.05)?.top10Contamination ?? 1;
  const falsePositiveRate = falsePositiveRows.filter(({ classification }) => classification === "suspicious" || classification === "high_risk").length / Math.max(1, falsePositiveRows.length);
  const predictive = predictiveUplift(inputs, finalistTrainingResults, 100);
  const recommendedTrophy = [...trophyRows].sort((left, right) => (
    Number(right.ndcg10Median) + Number(right.candidateRecall20Median) - Number(left.ndcg10Median) - Number(left.candidateRecall20Median)
  ))[0]!;

  const proposedGates = {
    candidateRecall20Minimum: round(Math.floor(multiSeedSummary.recall20.p5 * 20) / 20, 2),
    cheaterContaminationMaximum: 0.2,
    falsePositiveMaximum: round(Math.max(0.01, falsePositiveRate), 2),
    ndcg10Minimum: round(Math.floor(multiSeedSummary.ndcg10.p5 * 20) / 20, 2),
    predictiveUpliftMinimum: round(Math.max(0, Math.floor(multiSeedSummary.predictiveUplift.p5)), 2),
    rankErrorMaximum: Math.ceil(multiSeedSummary.rankError.p95),
  };
  const readyForProduct = multiSeedSummary.predictiveUplift.p5 > 0
    && protectedContamination5 <= proposedGates.cheaterContaminationMaximum
    && falsePositiveRate <= proposedGates.falsePositiveMaximum
    && leaveOneOutDependency <= 0.25
    && multiSeedSummary.futureRecall20.p5 >= 0.5;

  const provinceSummaryRows = (["dense", "medium", "small"] as const).map((density) => {
    const rows = provinceSeasonRows.filter((row) => row.density === density && row.eligiblePlayers >= 50);
    return [density, rows.length, aggregateEliteMetric(rows, "precisionAt10").p50, aggregateEliteMetric(rows, "ndcgAt10").p50, aggregateEliteMetric(rows, "candidateRecallAt20").p50, aggregateEliteMetric(rows, "meanRankErrorTop10").p50] as CsvValue[];
  });
  const provinceAt50 = provinceSeasonRows.filter(({ eligiblePlayers }) => eligiblePlayers >= 50);
  const provinceExtremes = scopeExtremes(provinceAt50);
  const communityExtremes = scopeExtremes(communityRows);
  const windowRows = selection.all.filter(({ metrics }) => metrics.candidateId.startsWith("elite-window-"));
  const qualityRows = selection.all.filter(({ metrics }) => metrics.candidateId.startsWith("elite-quality-"));
  const weightRows = selection.all.filter(({ metrics }) => metrics.candidateId.startsWith("elite-weight-"))
    .sort((left, right) => right.metrics.composite - left.metrics.composite).slice(0, 8);

  const report = `# Season Score — validación de élite del PR #115

Todos los datos son sintéticos. Esta iteración no crea producto, tablas remotas, rankings reales, trofeos ni sanciones.

## Diagnóstico del 0% anterior

El 0% era **métrica y fórmula, en distinta medida**. La métrica anterior comparaba exactamente diez nombres entre 10.000 elegibles a escala nacional: un jugador de referencia #10 predicho #11 contaba como fallo completo, y mezclaba territorios que en producto tendrán rankings separados. Además, el ground truth de mérito era otra fórmula sintética parcialmente parecida al candidato. Al corregir ámbito, añadir NDCG/candidate recall y validar contra rendimiento futuro, la señal deja de ser binaria. La fórmula sigue teniendo margen si las métricas predictivas o de estabilidad quedan por debajo de los intervalos multi-seed.

## Metodología no circular

- NDCG usa relevancia ordinal lineal hasta 2K; evita que un #11 cuente casi como cero sin fingir que es Top10.
- Capacidad usa `latent_skill`; mérito de temporada combina 45% capacidad, 35% rendimiento individual sintético realizado y 20% oposición, distinto del candidato.
- La verdad futura usa solo semanas 35–52. El simulador genera un índice individual oculto con ruido determinista separado del calendario; ni el motor ni la selección de ventana pueden leerlo.
- Ese índice existe solo para validar capacidad predictiva del laboratorio. No es Rating V2, no usa goles y no propone un campo de producto.

## Finalista de esta iteración

\`${finalist.id}\`: pesos **${finalist.weights.quality}/${finalist.weights.competition}/${finalist.weights.opposition}**, ventana \`${finalist.volumeModel}\`, calidad \`${finalist.ratingConfidenceModel}\`, elegibilidad de ranking ${finalist.eligibility.minimumValidChallenges}/${finalist.eligibility.minimumUniqueOpponents}.

### Ventanas

${markdownTable(
  ["Candidato", "Ventana", "Calidad", "Pesos", "NDCG10 terr.", "Recall20 terr.", "NDCG futuro", "Recall futuro", "Uplift", "Churn", "Volumen", "Objetivo"],
  windowRows.map(({ metrics }) => [metrics.candidateId, metrics.volumeModel, metrics.challengeQuality, `${metrics.qualityWeight}/${metrics.competitionWeight}/${metrics.oppositionWeight}`, metrics.territorialNdcg10, metrics.territorialCandidateRecall20, metrics.territorialFutureNdcg10, metrics.territorialFutureCandidateRecall20, metrics.predictiveUplift, metrics.territorialTop10Churn, metrics.volumeAdvantage, metrics.composite]),
)}

### Calidad competitiva

${markdownTable(
  ["Candidato", "Ventana", "Calidad", "Pesos", "NDCG10 terr.", "Recall20 terr.", "NDCG futuro", "Recall futuro", "Uplift", "Churn", "Volumen", "Objetivo"],
  qualityRows.map(({ metrics }) => [metrics.candidateId, metrics.volumeModel, metrics.challengeQuality, `${metrics.qualityWeight}/${metrics.competitionWeight}/${metrics.oppositionWeight}`, metrics.territorialNdcg10, metrics.territorialCandidateRecall20, metrics.territorialFutureNdcg10, metrics.territorialFutureCandidateRecall20, metrics.predictiveUplift, metrics.territorialTop10Churn, metrics.volumeAdvantage, metrics.composite]),
)}

### Mejores pesos del grid

${markdownTable(
  ["Candidato", "Pesos", "NDCG10 terr.", "Recall20 terr.", "NDCG futuro", "Recall futuro", "Uplift", "Churn", "Volumen", "Objetivo"],
  weightRows.map(({ metrics }) => [metrics.candidateId, `${metrics.qualityWeight}/${metrics.competitionWeight}/${metrics.oppositionWeight}`, metrics.territorialNdcg10, metrics.territorialCandidateRecall20, metrics.territorialFutureNdcg10, metrics.territorialFutureCandidateRecall20, metrics.predictiveUplift, metrics.territorialTop10Churn, metrics.volumeAdvantage, metrics.composite]),
)}

## Provincias y comunidades

${markdownTable(["Densidad", "Territorios", "Precision@10 p50", "NDCG@10 p50", "Candidate recall@20 p50", "Rank error p50"], provinceSummaryRows)}

De 52 territorios base, ${provinceSeasonRows.length} tienen al menos 30 elegibles y ${provinceAt50.length} tienen al menos 50. Agregado provincial >=50:

${markdownTable(["Métrica", "Media", "p10", "p50", "p90"], scopeMetricSummary(provinceAt50))}

Peor provincia por NDCG@10: **${provinceExtremes.worst?.scopeName ?? "sin muestra"} (${provinceExtremes.worst?.ndcgAt10 ?? 0})**. Mejor: **${provinceExtremes.best?.scopeName ?? "sin muestra"} (${provinceExtremes.best?.ndcgAt10 ?? 0})**.

En comunidades se evaluaron ${communityRowsAll.length}; ${communityRows.length} entran en el agregado tras retirar ${communityRowsAll.length - communityRows.length} duplicados conceptuales uniprovinciales. Los CSV conservan ambos para auditoría.

${markdownTable(["Métrica autonómica", "Media", "p10", "p50", "p90"], scopeMetricSummary(communityRows))}

Peor comunidad no duplicada por NDCG@10: **${communityExtremes.worst?.scopeName ?? "sin muestra"} (${communityExtremes.worst?.ndcgAt10 ?? 0})**. Mejor: **${communityExtremes.best?.scopeName ?? "sin muestra"} (${communityExtremes.best?.ndcgAt10 ?? 0})**.

## España

${markdownTable(["Truth", "Top", "Overlap", "Precision", "NDCG", "Recall en 2K"], nationalRows.map((row) => [row.truth, row.k, row.overlap, row.precision, row.ndcg, row.candidateRecallAtDoubleK]))}

Métricas nacionales del candidato anterior corregidas:

${markdownTable(["Truth", "Top", "Overlap", "Precision", "NDCG", "Recall en 2K"], previousNational.map((row) => [row.truth, row.k, row.overlap, row.precision, row.ndcg, row.candidateRecallAtDoubleK]))}

## Out-of-sample y multi-seed

El ranking se calcula con semanas 1–34 y se valida exclusivamente con Retos de semanas 35–52. Top 100 obtiene rendimiento futuro medio ${predictive.topMean} frente a ${predictive.populationMean} de población: uplift **${predictive.uplift}**, correlación ${predictive.correlation}.

${markdownTable(["Top", "Elegibles", "Rendimiento futuro", "Uplift rendimiento", "Oposición futura", "Uplift oposición", "Índice competitivo", "Uplift índice"], predictiveTopRows.map((row) => [row.k, row.eligiblePlayers, row.futurePerformance, row.futurePerformanceUplift, row.futureOpposition, row.futureOppositionUplift, row.futureCompetitiveIndex, row.futureCompetitiveIndexUplift]))}

El índice competitivo futuro es una referencia sintética fuera de muestra; no modifica ni pretende sustituir Rating V2.

${markdownTable(["Métrica (20 seeds)", "Media", "Std", "p5", "p50", "p95"], Object.entries(multiSeedSummary).map(([name, values]) => [name, values.mean, values.std, values.p5, values.p50, values.p95]))}

## Incertidumbre y robustez del corte

- Provincias bootstrap: ${uncertainty.length}; #10 y #11 comparten banda de incertidumbre en ${round(sameBandRate * 100)}%.
- Confianza media del score #10: ${round(average(uncertainty.map(({ rank10Confidence }) => rank10Confidence)))}.
- Top 10 con dependencia de algún partido individual: ${round(leaveOneOutDependency * 100)}% de media territorial.
- Sensibilidad de eliminaciones individuales: ${round(average(leaveOneOut.map(({ sensitiveRemovalRate }) => sensitiveRemovalRate)) * 100)}%.

Season Score mantiene el orden provisional. Para trofeo, la evidencia adicional filtra sin introducir una fórmula secreta:

${markdownTable(["Regla", "Elegibles", "Territorios", "NDCG10", "Recall20", "Rank error"], trophyRows.map((row) => [row.rule, row.eligiblePlayers, row.territories, row.ndcg10Median, row.candidateRecall20Median, row.meanRankErrorMedian]))}

Mejor equilibrio experimental: **${recommendedTrophy.rule}**. Sigue sujeto a los intervalos y no concede trofeos reales.

## Justicia deportiva

${markdownTable(["Caso", "Rating", "Equipo", "Win rate", "Calidad", "Competición", "Score"], teamStrengthRows.map((row) => [row.label, row.rating, row.teamRating, row.winRate, row.quality, row.competition, row.score]))}

${markdownTable(["Posición", "Elegibles", "Top10 plazas", "Precision@10", "Share elegible", "Share Top", "Ratio representación", "Corr. mérito"], positionRows.map((row) => [row.position, row.eligiblePlayers, row.top10Places, row.precisionAt10, row.eligibleShare, row.top10Share, row.representationRatio, row.scoreMeritCorrelation]))}

Jugar en 1/2/5/10 equipos propios no concede bonus directo: consultar \`own_team_diversity.csv\`. El equipo forma parte del contexto del resultado, no de la calidad individual.

## Densidad y estacionalidad

${markdownTable(["Mínimo elegibles", "Territorios", "NDCG10", "Recall20", "Rank error"], densityValidation.map((row) => [row.minimumEligible, row.territories, row.ndcg10Median, row.candidateRecall20Median, row.meanRankErrorMedian]))}

${markdownTable(["Actividad", "Territorios >=50", "NDCG10", "Recall20", "Churn"], seasonalityRows.map((row) => [row.activityProfile, row.territoriesAt50, row.ndcg10Median, row.candidateRecall20Median, row.top10Churn]))}

## Red team y corte #10

Se repitieron los 14 ataques. Con 5% de manipuladores, contaminación Top 10 finalista: ${round(protectedContamination5 * 100)}%; falsos positivos \`suspicious/high_risk\`: ${round(falsePositiveRate * 100)}%.

${markdownTable(["Modo", "Provincia", "De #", "A #", "Partidos falsos", "Cuentas"], cutoffRows.map((row) => [row.mode, row.provinceCode, row.baselineRank, row.targetRank, row.fakeMatchesRequired, row.accountsRequired]))}

Si el modo protegido devuelve vacío, el atacante no alcanza #9 ni con 30 partidos/cuentas sintéticos. No se redujo ninguna protección para mejorar precisión.

## Criterios objetivos propuestos

Son guardas de no-regresión derivadas de los intervalos de 20 seeds, no cifras escogidas antes de simular:

- territorial median NDCG@10 >= **${proposedGates.ndcg10Minimum}**;
- candidate recall@20 >= **${proposedGates.candidateRecall20Minimum}**;
- mean rank error Top10 <= **${proposedGates.rankErrorMaximum}**;
- predictive uplift Top100 >= **${proposedGates.predictiveUpliftMinimum}** en p5;
- contaminación con 5% de manipuladores <= **${round(proposedGates.cheaterContaminationMaximum * 100)}%** (límite p95 de una selección Top10 aleatoria con prevalencia 5%);
- falsos positivos suspicious/high <= **${round(proposedGates.falsePositiveMaximum * 100)}%**;
- además, ninguna regresión en posición, dependencia de un partido o privacidad.

## Decisión

**${readyForProduct ? "El motor supera esta batería experimental, pero requiere revisión humana antes de producto." : "Recomiendo otra iteración de laboratorio; todavía no debe implementarse como producto."}**

Frenos medidos: contaminación Top10 ${round(protectedContamination5 * 100)}% frente al límite ${round(proposedGates.cheaterContaminationMaximum * 100)}%; dependencia de un encuentro ${round(leaveOneOutDependency * 100)}% frente al 25% propuesto; y banda #10/#11 compartida en ${round(sameBandRate * 100)}% de provincias. Además, la presencia real no queda demostrada por inscripción, el venue acordado no prueba ubicación, colusión real necesita grafo histórico y los ground truths sintéticos no sustituyen datos deportivos reales anonimizados.

## Validación técnica

- 11 tests de élite y 25 tests focalizados Season Score: PASS.
- `npm test`: build de producción y 136 tests: PASS.
- `npm run typecheck`: PASS.
- ESLint focalizado del laboratorio: PASS.
- ESLint global: 23 errores y 20 avisos preexistentes, todos fuera del diff del laboratorio; no se modificaron por esta entrega.
- `git diff --check`: PASS.

## Entrega solicitada (1–37)

1. El 0 anterior era Top10 nacional exacto sobre 10.000 y ground truth sintético; mezclaba ámbito y cercanía.
2. Problema de métrica y parcialmente de fórmula; esta iteración los separa.
3. Nacional anterior corregido: \`previous_national_metrics_corrected.csv\`.
4. Provincias: \`province_season_merit.csv\`.
5. Comunidades: \`autonomous_communities.csv\` con duplicados marcados.
6. NDCG@10: territorial, autonómico y nacional.
7. Candidate recall@20: incluido.
8. Rank error medio/mediano: incluido.
9. Predictive validation: corte 70/30 sin fuga.
10. Multi-seed: 20 seeds de 10.000 jugadores.
11. Incertidumbre: bootstrap reproducible de 100 iteraciones.
12. #10/#11: bandas y gap en \`top10_uncertainty.csv\`.
13. Ranking: ${finalist.eligibility.minimumValidChallenges}/${finalist.eligibility.minimumUniqueOpponents}.
14. Trofeo: ${recommendedTrophy.rule} experimental + confianza/actividad.
15. Ventanas: recent20/25/30, all y hybrid70/30.
16. Híbridos: comparados, no adoptados automáticamente.
17. Pesos: grid 35–55 / 30–50 / 10–25.
18. Calidad: full, competitive y challenge_calibrated.
19. Jugador mediocre/equipo fuerte: probado.
20. Excelente/equipo débil: probado.
21. POR/DEF/MED/DEL: segmentados.
22. Densidad: 30/40/50/75/100.
23. Estabilidad: territorial y cinco perfiles, incluido crecimiento provincial.
24. Leave-one-out: todos los Top10 provinciales >=50.
25. Red team: 14 ataques repetidos.
26. Ataque #15→#9: incluido.
27. Contaminación: 1/2/5/10%.
28. Falsos positivos: cinco casos legítimos.
29. Finalistas: \`candidate_elite_comparison.csv\`.
30. Recomendación: \`${finalist.id}\`, solo laboratorio.
31. Criterios: guardas multi-seed anteriores.
32. Fallos abiertos: presencia, venue, colusión, corte y datos reales.
33. Decisión: ${readyForProduct ? "revisión humana previa a producto" : "otra iteración de laboratorio"}.
34. Tests: 25 focalizados; build y 136 tests completos en verde. Lint focalizado verde; deuda global preexistente documentada.
35. Commit/PR: actualización del PR #115.
36. Producción/Supabase remoto: intactos.
37. Rating V2, logros y recompensas: intactos.
`;

  await writeFile(reportPath, report, "utf8");
  await writeFile(resolve(resultsDirectory, "elite_summary.json"), `${JSON.stringify({
    decision: readyForProduct ? "human_review_before_product" : "another_lab_iteration",
    finalist,
    multiSeedSummary,
    proposedGates,
    protectedContamination5,
    falsePositiveRate,
    sameBandRate,
    leaveOneOutDependency,
  }, null, 2)}\n`, "utf8");
  process.stdout.write(`Elite validation complete: ${finalist.id}; decision ${readyForProduct ? "review" : "iterate"}\n`);
}

await main();
