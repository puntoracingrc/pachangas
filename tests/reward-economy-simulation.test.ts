import assert from "node:assert/strict";
import test from "node:test";

type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary";
type PoolEntry = {
  cosmeticKey?: string;
  duplicatePoints?: number;
  kind: "combination" | "player_cosmetic" | "points";
  points: [number, number];
  weight: number;
};

const pools: Record<Rarity, PoolEntry[]> = {
  common: [
    { kind: "points", points: [4, 7], weight: 70 },
    { cosmeticKey: "symbol.ball", duplicatePoints: 4, kind: "player_cosmetic", points: [0, 0], weight: 10 },
    { cosmeticKey: "pattern.stripes", duplicatePoints: 4, kind: "player_cosmetic", points: [0, 0], weight: 10 },
    { cosmeticKey: "symbol.ball", duplicatePoints: 4, kind: "combination", points: [3, 5], weight: 10 },
  ],
  uncommon: [
    { kind: "points", points: [7, 11], weight: 65 },
    { cosmeticKey: "pattern.diagonal", duplicatePoints: 8, kind: "player_cosmetic", points: [0, 0], weight: 11 },
    { cosmeticKey: "border.double", duplicatePoints: 8, kind: "player_cosmetic", points: [0, 0], weight: 11 },
    { cosmeticKey: "adornment.ribbon", duplicatePoints: 8, kind: "combination", points: [5, 8], weight: 13 },
  ],
  rare: [
    { kind: "points", points: [12, 18], weight: 60 },
    { cosmeticKey: "border.silver", duplicatePoints: 16, kind: "player_cosmetic", points: [0, 0], weight: 12 },
    { cosmeticKey: "border.laurel", duplicatePoints: 16, kind: "player_cosmetic", points: [0, 0], weight: 12 },
    { cosmeticKey: "adornment.star", duplicatePoints: 16, kind: "combination", points: [8, 12], weight: 16 },
  ],
  epic: [
    { kind: "points", points: [20, 30], weight: 55 },
    { cosmeticKey: "border.gold", duplicatePoints: 28, kind: "player_cosmetic", points: [0, 0], weight: 13 },
    { cosmeticKey: "symbol.crown", duplicatePoints: 28, kind: "player_cosmetic", points: [0, 0], weight: 12 },
    { cosmeticKey: "palette.gold", duplicatePoints: 28, kind: "combination", points: [14, 20], weight: 20 },
  ],
  legendary: [
    { kind: "points", points: [35, 50], weight: 50 },
    { cosmeticKey: "effect.glow", duplicatePoints: 45, kind: "player_cosmetic", points: [0, 0], weight: 25 },
    { cosmeticKey: "effect.glow", duplicatePoints: 45, kind: "combination", points: [25, 35], weight: 25 },
  ],
};

export type EconomySimulation = {
  boxes: number;
  cosmetics: number;
  duplicates: number;
  matches: number;
  months: 3 | 6 | 12;
  points: number;
  rarity: Record<Rarity, number>;
  weeklyMatches: 1 | 2 | 4;
};

function randomFactory(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function tierUp(rarity: Rarity): Rarity {
  if (rarity === "common") return "uncommon";
  if (rarity === "uncommon") return "rare";
  if (rarity === "rare") return "epic";
  return "legendary";
}

function simulate(weeklyMatches: 1 | 2 | 4, months: 3 | 6 | 12): EconomySimulation {
  const matches = weeklyMatches * (months === 3 ? 13 : months === 6 ? 26 : 52);
  const random = randomFactory(0x51a7 + weeklyMatches * 100 + months);
  const owned = new Set<string>();
  const rarity: Record<Rarity, number> = { common: 0, uncommon: 0, rare: 0, epic: 0, legendary: 0 };
  let points = 0;
  let boxes = 0;
  let duplicates = 0;
  let wins = 0;
  let cleanSheets = 0;
  let bigWins = 0;
  let teamGoals = 0;
  let firstWin = true;
  let firstClean = true;
  let firstBig = true;
  let firstClose = true;

  function openBox(boxRarity: Rarity) {
    boxes += 1;
    rarity[boxRarity] += 1;
    const entries = pools[boxRarity];
    const ticket = random() * entries.reduce((sum, entry) => sum + entry.weight, 0);
    let ceiling = 0;
    const entry = entries.find((candidate) => {
      ceiling += candidate.weight;
      return ticket < ceiling;
    }) ?? entries.at(-1)!;
    points += entry.points[0] + Math.floor(random() * (entry.points[1] - entry.points[0] + 1));
    if (entry.cosmeticKey) {
      if (owned.has(entry.cosmeticKey)) {
        duplicates += 1;
        points += entry.duplicatePoints ?? 0;
      } else {
        owned.add(entry.cosmeticKey);
      }
    }
  }

  function milestone(value: number, thresholds: Array<[number, Rarity]>) {
    for (const [threshold, baseRarity] of thresholds) {
      if (value === threshold) openBox(tierUp(baseRarity));
    }
  }

  for (let match = 1; match <= matches; match += 1) {
    const goalRoll = random();
    const goals = goalRoll < 0.08 ? 0 : goalRoll < 0.23 ? 1 : goalRoll < 0.45 ? 2
      : goalRoll < 0.67 ? 3 : goalRoll < 0.83 ? 4 : goalRoll < 0.93 ? 5 : 6;
    teamGoals += goals;
    if (goals >= 2) openBox(goals === 2 ? "common" : goals <= 4 ? "uncommon" : goals === 5 ? "rare" : "epic");

    const won = random() < 0.45;
    if (won) {
      wins += 1;
      openBox(firstWin ? "uncommon" : "common");
      firstWin = false;
      const margin = random();
      if (margin < 0.18) {
        bigWins += 1;
        openBox(firstBig ? "rare" : "uncommon");
        firstBig = false;
      } else if (margin < 0.58) {
        openBox(firstClose ? "uncommon" : "common");
        firstClose = false;
      }
    }
    if (random() < 0.12) {
      cleanSheets += 1;
      openBox(firstClean ? "uncommon" : "common");
      firstClean = false;
    }

    milestone(match, [[1, "common"], [5, "uncommon"], [10, "uncommon"], [25, "rare"], [50, "epic"]]);
    milestone(wins, [[5, "uncommon"], [10, "rare"], [25, "epic"]]);
    milestone(cleanSheets, [[5, "rare"]]);
    milestone(bigWins, [[5, "rare"]]);
    milestone(teamGoals, [[25, "uncommon"], [100, "rare"]]);
  }

  return { boxes, cosmetics: owned.size, duplicates, matches, months, points, rarity, weeklyMatches };
}

export function rewardEconomyScenarios() {
  const profiles = [1, 2, 4] as const;
  const periods = [3, 6, 12] as const;
  return profiles.flatMap((weeklyMatches) => periods.map((months) => simulate(weeklyMatches, months)));
}

test("conservative reward economy grows with activity without becoming explosive", () => {
  const scenarios = rewardEconomyScenarios();
  for (const weeklyMatches of [1, 2, 4] as const) {
    const profile = scenarios.filter((scenario) => scenario.weeklyMatches === weeklyMatches);
    assert.deepEqual(profile.map((scenario) => scenario.months), [3, 6, 12]);
    assert.ok(profile[0].points < profile[1].points && profile[1].points < profile[2].points);
    assert.ok(profile[0].boxes < profile[1].boxes && profile[1].boxes < profile[2].boxes);
  }
  const annualVeryActive = scenarios.find((scenario) => scenario.weeklyMatches === 4 && scenario.months === 12)!;
  assert.ok(annualVeryActive.boxes < 700, `Unexpected annual box inflation: ${annualVeryActive.boxes}`);
  assert.ok(annualVeryActive.points < 10_000, `Unexpected annual point inflation: ${annualVeryActive.points}`);
  assert.ok(annualVeryActive.cosmetics <= 12);
  assert.ok(annualVeryActive.duplicates < annualVeryActive.boxes);
});

test("every simulated box is cosmetic progression and never a sporting modifier", () => {
  for (const entries of Object.values(pools)) {
    for (const entry of entries) {
      assert.ok(["points", "player_cosmetic", "combination"].includes(entry.kind));
      assert.equal("rating" in entry, false);
      assert.equal("facets" in entry, false);
    }
  }
});
