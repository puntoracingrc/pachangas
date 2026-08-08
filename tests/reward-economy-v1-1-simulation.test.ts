import assert from "node:assert/strict";
import test from "node:test";
import { resolveGoalRewardComponents } from "./achievement-catalog-v3-model";

type Rarity = "common" | "epic" | "legendary" | "rare" | "uncommon";
type Scenario = {
  averageBoxesPerMatch: number;
  averageCosmetics: number;
  averageDuplicates: number;
  averagePoints: number;
  boxesPerYear: number;
  maxBoxesPerMatch: number;
  model: "V1" | "V1.1";
  months: 3 | 6 | 12;
  p50: number;
  p90: number;
  p95: number;
  pointsPerYear: number;
  weeklyMatches: 1 | 2 | 4;
  winRate: 0.5 | 0.7 | 0.85;
};

const pointsByRarity: Record<Rarity, number> = {
  common: 5.5,
  uncommon: 9,
  rare: 15,
  epic: 25,
  legendary: 42.5,
};
const rarityOrder: Rarity[] = ["common", "uncommon", "rare", "epic", "legendary"];
const trajectoryMilestones: Array<[number, Rarity]> = [
  [1, "common"], [5, "uncommon"], [10, "uncommon"], [25, "rare"],
  [50, "rare"], [100, "epic"], [250, "epic"], [500, "legendary"],
];

function randomFactory(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function poisson(random: () => number, lambda: number) {
  const limit = Math.exp(-lambda);
  let product = 1;
  let count = 0;
  do {
    count += 1;
    product *= random();
  } while (product > limit);
  return count - 1;
}

function percentile(values: number[], fraction: number) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)] ?? 0;
}

function rounded(value: number, digits = 2) {
  const scale = 10 ** digits;
  return Math.round(value * scale) / scale;
}

function tierUp(rarity: Rarity) {
  return rarityOrder[Math.min(rarityOrder.length - 1, rarityOrder.indexOf(rarity) + 1)]!;
}

function simulate(
  model: Scenario["model"],
  weeklyMatches: Scenario["weeklyMatches"],
  months: Scenario["months"],
  winRate: Scenario["winRate"],
  seed: number,
) {
  const matches = weeklyMatches * (months === 3 ? 13 : months === 6 ? 26 : 52);
  const random = randomFactory(seed);
  const boxesPerMatch: number[] = [];
  const firstFamilies = new Set<string>();
  const milestones = new Set<number>();
  const cosmetics = new Set<string>();
  let boxes = 0;
  let points = 0;
  let duplicates = 0;

  function openBox(baseRarity: Rarity, family: string) {
    const rarity = firstFamilies.has(family) ? baseRarity : tierUp(baseRarity);
    firstFamilies.add(family);
    boxes += 1;
    points += pointsByRarity[rarity];
    const cosmeticChance = rarity === "legendary" ? 0.5
      : rarity === "epic" ? 0.45 : rarity === "rare" ? 0.4
        : rarity === "uncommon" ? 0.35 : 0.3;
    if (random() < cosmeticChance) {
      const cosmetic = `${rarity}.${Math.floor(random() * (rarity === "legendary" ? 2 : 4))}`;
      if (cosmetics.has(cosmetic)) duplicates += 1;
      else cosmetics.add(cosmetic);
    }
  }

  for (let match = 1; match <= matches; match += 1) {
    const boxesBefore = boxes;
    const won = random() < winRate;
    const drawn = !won && random() < 0.28;
    let goalsFor = poisson(random, 1.75 + (winRate - 0.5) * 1.7);
    let goalsAgainst = poisson(random, 1.45 - (winRate - 0.5) * 0.65);
    if (won && goalsFor <= goalsAgainst) goalsFor = goalsAgainst + 1;
    if (drawn) goalsFor = goalsAgainst;
    if (!won && !drawn && goalsFor >= goalsAgainst) goalsAgainst = goalsFor + 1;

    if (won) openBox("common", "victoria_reto");

    if (goalsFor >= 2) {
      if (model === "V1") {
        const rarity: Rarity = goalsFor === 2 ? "common"
          : goalsFor <= 4 ? "uncommon" : goalsFor === 5 ? "rare" : "epic";
        openBox(rarity, `goals.${Math.min(goalsFor, 6)}`);
      } else {
        for (const component of resolveGoalRewardComponents(goalsFor)) {
          openBox(component.boxRarity, `goals.${goalsFor}`);
        }
      }
    }

    const difference = goalsFor - goalsAgainst;
    if (goalsAgainst === 0) openBox("common", "clean_sheet");
    if (won && difference >= 4) openBox("uncommon", "big_win");
    if (won && difference === 1) openBox("common", "close_win");
    if (model === "V1.1" && won && difference >= 4 && goalsAgainst === 0) {
      openBox("rare", "absolute_dominance");
    }

    const milestone = trajectoryMilestones.find(([threshold]) => threshold === match);
    if (milestone && !milestones.has(milestone[0])) {
      milestones.add(milestone[0]);
      openBox(milestone[1], "team.matches");
    }
    boxesPerMatch.push(boxes - boxesBefore);
  }
  return { boxes, boxesPerMatch, cosmetics: cosmetics.size, duplicates, matches, points };
}

export function rewardEconomyV11Scenarios(iterations = 180): Scenario[] {
  const frequencies = [1, 2, 4] as const;
  const periods = [3, 6, 12] as const;
  const winRates = [0.5, 0.7, 0.85] as const;
  const models = ["V1", "V1.1"] as const;
  return models.flatMap((model) => frequencies.flatMap((weeklyMatches) => periods.flatMap((months) => (
    winRates.map((winRate) => {
      const runs = Array.from({ length: iterations }, (_, index) => simulate(
        model, weeklyMatches, months, winRate,
        0x1100 + index + weeklyMatches * 10_000 + months * 100
          + Math.round(winRate * 100) + (model === "V1.1" ? 1_000_000 : 0),
      ));
      const allMatches = runs.flatMap((run) => run.boxesPerMatch);
      const averagePoints = runs.reduce((sum, run) => sum + run.points, 0) / iterations;
      const annualFactor = 12 / months;
      return {
        averageBoxesPerMatch: rounded(
          runs.reduce((sum, run) => sum + run.boxes, 0)
            / runs.reduce((sum, run) => sum + run.matches, 0),
        ),
        averageCosmetics: rounded(runs.reduce((sum, run) => sum + run.cosmetics, 0) / iterations),
        averageDuplicates: rounded(runs.reduce((sum, run) => sum + run.duplicates, 0) / iterations),
        averagePoints: rounded(averagePoints),
        boxesPerYear: rounded(
          runs.reduce((sum, run) => sum + run.boxes, 0) / iterations * annualFactor,
        ),
        maxBoxesPerMatch: Math.max(...allMatches),
        model,
        months,
        p50: percentile(allMatches, 0.5),
        p90: percentile(allMatches, 0.9),
        p95: percentile(allMatches, 0.95),
        pointsPerYear: rounded(averagePoints * annualFactor),
        weeklyMatches,
        winRate,
      };
    })
  ))));
}

test("V1.1 simulation covers every requested cadence, period and win rate", () => {
  const scenarios = rewardEconomyV11Scenarios(80);
  assert.equal(scenarios.length, 54);
  assert.ok(scenarios.every((scenario) => scenario.averageBoxesPerMatch > 0));
  assert.ok(scenarios.every((scenario) => scenario.p95 >= scenario.p90));
  assert.ok(scenarios.every((scenario) => scenario.maxBoxesPerMatch >= scenario.p95));
});

test("multiple goal components and Dominio absoluto increase rewards without a cap", () => {
  const scenarios = rewardEconomyV11Scenarios(100);
  for (const v11 of scenarios.filter((scenario) => scenario.model === "V1.1")) {
    const v1 = scenarios.find((scenario) => scenario.model === "V1"
      && scenario.weeklyMatches === v11.weeklyMatches
      && scenario.months === v11.months
      && scenario.winRate === v11.winRate);
    assert.ok(v1);
    assert.ok(v11.averageBoxesPerMatch >= v1.averageBoxesPerMatch - 0.12);
  }
  assert.ok(Math.max(...scenarios.map((scenario) => scenario.maxBoxesPerMatch)) >= 7);
});
