import { round } from "./random";
import { expectedResult, isSeasonScoreEvidence } from "./engine";
import type { FormulaMetrics, RankedPlayer, SeasonPlayerInput, SyntheticPlayer } from "./types";

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

export function pearson(left: number[], right: number[]) {
  if (left.length !== right.length || left.length < 2) return 0;
  const leftMean = average(left);
  const rightMean = average(right);
  let covariance = 0;
  let leftVariance = 0;
  let rightVariance = 0;
  for (let index = 0; index < left.length; index += 1) {
    const leftDelta = left[index]! - leftMean;
    const rightDelta = right[index]! - rightMean;
    covariance += leftDelta * rightDelta;
    leftVariance += leftDelta ** 2;
    rightVariance += rightDelta ** 2;
  }
  return leftVariance === 0 || rightVariance === 0 ? 0 : covariance / Math.sqrt(leftVariance * rightVariance);
}

function ranks(values: number[]) {
  const sorted = values.map((value, index) => ({ index, value }))
    .sort((left, right) => right.value - left.value || left.index - right.index);
  const result = new Array<number>(values.length);
  sorted.forEach(({ index }, rank) => { result[index] = rank + 1; });
  return result;
}

export function spearman(left: number[], right: number[]) {
  return pearson(ranks(left), ranks(right));
}

function competitiveMerit(input: SeasonPlayerInput) {
  const records = input.records.filter(isSeasonScoreEvidence);
  if (records.length === 0) return input.player.latentSkill * 0.55 + 25;
  const performance = records.reduce((sum, record) => (
    sum + Math.max(0, Math.min(100, 50 + (record.result - expectedResult(input.player.latentSkill, record.opponentRating)) * 85))
  ), 0) / records.length;
  const opposition = records.reduce((sum, record) => sum + record.opponentRating, 0) / records.length;
  return input.player.latentSkill * 0.55 + performance * 0.3 + opposition * 0.15;
}

function topPrecision(results: RankedPlayer[], meritsById: Map<string, number>, size: number) {
  const eligible = results.filter(({ eligibility }) => eligibility.eligible);
  const predicted = new Set([...eligible]
    .sort((left, right) => right.score - left.score)
    .slice(0, size)
    .map(({ playerId }) => playerId));
  const expected = new Set([...eligible]
    .sort((left, right) => (meritsById.get(right.playerId) ?? 0) - (meritsById.get(left.playerId) ?? 0))
    .slice(0, size)
    .map(({ playerId }) => playerId));
  return predicted.size === 0 ? 0 : [...predicted].filter((id) => expected.has(id)).length / predicted.size;
}

function residualVolumeAdvantage(
  results: RankedPlayer[],
  inputsById: Map<string, SeasonPlayerInput>,
  playersById: Map<string, SyntheticPlayer>,
) {
  const eligible = results.filter(({ eligibility }) => eligibility.eligible);
  if (eligible.length < 2) return 0;
  const scores = eligible.map(({ score }) => score);
  const skills = eligible.map(({ playerId }) => playersById.get(playerId)?.latentSkill ?? 0);
  const skillMean = average(skills);
  const scoreMean = average(scores);
  const covariance = skills.reduce((sum, skill, index) => sum + (skill - skillMean) * (scores[index]! - scoreMean), 0);
  const variance = skills.reduce((sum, skill) => sum + (skill - skillMean) ** 2, 0);
  const slope = variance === 0 ? 0 : covariance / variance;
  const intercept = scoreMean - slope * skillMean;
  const residuals = scores.map((score, index) => score - (intercept + slope * skills[index]!));
  return pearson(residuals, eligible.map(({ playerId }) => inputsById.get(playerId)?.records.length ?? 0));
}

export function evaluateFormula(
  candidateId: string,
  inputs: SeasonPlayerInput[],
  results: RankedPlayer[],
): FormulaMetrics {
  const playersById = new Map(inputs.map(({ player }) => [player.id, player]));
  const inputsById = new Map(inputs.map((input) => [input.player.id, input]));
  const meritsById = new Map(inputs.map((input) => [input.player.id, competitiveMerit(input)]));
  const eligible = results.filter(({ eligibility }) => eligibility.eligible);
  const scores = eligible.map(({ score }) => score);
  const skills = eligible.map(({ playerId }) => playersById.get(playerId)?.latentSkill ?? 0);
  const merits = eligible.map(({ playerId }) => meritsById.get(playerId) ?? 0);
  return {
    candidateId,
    eligiblePlayers: eligible.length,
    rankCorrelation: round(spearman(scores, merits), 4),
    scoreSkillCorrelation: round(pearson(scores, skills), 4),
    top10Precision: round(topPrecision(results, meritsById, 10), 4),
    top50Precision: round(topPrecision(results, meritsById, 50), 4),
    top100Precision: round(topPrecision(results, meritsById, 100), 4),
    volumeAdvantage: round(residualVolumeAdvantage(results, inputsById, playersById), 4),
  };
}

export function rankingChurn(previous: RankedPlayer[], current: RankedPlayer[], topSize: number) {
  const previousTop = new Set(previous.filter(({ eligibility }) => eligibility.eligible)
    .sort((left, right) => right.score - left.score).slice(0, topSize).map(({ playerId }) => playerId));
  const currentTop = new Set(current.filter(({ eligibility }) => eligibility.eligible)
    .sort((left, right) => right.score - left.score).slice(0, topSize).map(({ playerId }) => playerId));
  if (previousTop.size === 0 && currentTop.size === 0) return 0;
  const retained = [...currentTop].filter((playerId) => previousTop.has(playerId)).length;
  return round(1 - retained / Math.max(previousTop.size, currentTop.size), 4);
}
