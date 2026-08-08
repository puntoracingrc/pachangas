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

const matchMilestones: Array<[number, Rarity]> = [
  [1, "common"], [5, "common"], [10, "uncommon"], [25, "uncommon"],
  [50, "rare"], [100, "rare"], [250, "epic"], [500, "legendary"],
];
const winMilestones: Array<[number, Rarity]> = [
  [5, "uncommon"], [10, "uncommon"], [25, "rare"], [50, "rare"],
  [100, "epic"], [250, "legendary"],
];
const winStreakMilestones: Array<[number, Rarity]> = [
  [3, "uncommon"], [5, "rare"], [10, "epic"], [15, "legendary"],
];
const unbeatenMilestones: Array<[number, Rarity]> = [
  [3, "common"], [5, "uncommon"], [10, "rare"], [20, "legendary"],
];
const opponentMilestones: Array<[number, Rarity]> = [
  [3, "common"], [5, "common"], [10, "uncommon"], [25, "rare"], [50, "epic"],
];
const opponentWinMilestones: Array<[number, Rarity]> = [
  [3, "uncommon"], [5, "uncommon"], [10, "rare"], [25, "epic"], [50, "legendary"],
];
const playerGoalMilestones = [1, 10, 25, 50, 100, 250, 500];

export type EconomySimulationSummary = {
  averageBoxesPerMatch: number;
  averageBoxesPerSeason: number;
  averageCollectiveAchievements: number;
  averageCosmetics: number;
  averageDuplicates: number;
  averageIndividualAchievements: number;
  averagePoints: number;
  matches: number;
  maxBoxesPerMatch: number;
  months: 3 | 6 | 12;
  p50BoxesPerMatch: number;
  p90BoxesPerMatch: number;
  weeklyMatches: 1 | 2 | 4;
  winRate: 0.5 | 0.7 | 0.85;
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

function percentile(values: number[], fraction: number) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)] ?? 0;
}

function rounded(value: number, digits = 2) {
  const scale = 10 ** digits;
  return Math.round(value * scale) / scale;
}

function simulateSeason(
  weeklyMatches: 1 | 2 | 4,
  months: 3 | 6 | 12,
  winRate: 0.5 | 0.7 | 0.85,
  seed: number,
) {
  const matches = weeklyMatches * (months === 3 ? 13 : months === 6 ? 26 : 52);
  const random = randomFactory(seed);
  const owned = new Set<string>();
  const firstOccurrences = new Set<string>();
  const collectiveMilestones = new Set<string>();
  const individualMilestones = new Set<string>();
  const boxesPerMatch: number[] = [];
  const seenOpponents = new Set<number>();
  const beatenOpponents = new Set<number>();
  let points = 0;
  let boxes = 0;
  let duplicates = 0;
  let individualAchievements = 0;
  let playerGoals = 0;
  let wins = 0;
  let currentWinStreak = 0;
  let bestWinStreak = 0;
  let currentUnbeaten = 0;
  let bestUnbeaten = 0;

  function openBox(baseRarity: Rarity, occurrenceKey: string) {
    const isFirst = !firstOccurrences.has(occurrenceKey);
    firstOccurrences.add(occurrenceKey);
    const boxRarity = isFirst ? tierUp(baseRarity) : baseRarity;
    boxes += 1;
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

  function oneTimeMilestone(value: number, thresholds: Array<[number, Rarity]>, family: string) {
    const match = thresholds.find(([threshold]) => threshold === value);
    const key = match ? `${family}.${match[0]}` : "";
    if (match && !collectiveMilestones.has(key)) {
      collectiveMilestones.add(key);
      openBox(match[1], key);
    }
  }

  function individualMilestone(
    value: number,
    thresholds: number[],
    family: string,
    previousValue = value - 1,
  ) {
    for (const threshold of thresholds) {
      const key = `${family}.${threshold}`;
      if (threshold > previousValue && threshold <= value && !individualMilestones.has(key)) {
        individualMilestones.add(key);
        individualAchievements += 1;
      }
    }
  }

  for (let match = 1; match <= matches; match += 1) {
    const boxesBefore = boxes;
    const opponent = 1 + Math.floor(random() * Math.min(50, Math.max(4, Math.ceil(matches / 3))));
    seenOpponents.add(opponent);

    const won = random() < winRate;
    const drawn = !won && random() < 0.28;
    if (won) {
      wins += 1;
      currentWinStreak += 1;
      currentUnbeaten += 1;
      beatenOpponents.add(opponent);
      openBox("common", "team.external.wins.001");
    } else if (drawn) {
      currentWinStreak = 0;
      currentUnbeaten += 1;
    } else {
      currentWinStreak = 0;
      currentUnbeaten = 0;
    }
    bestWinStreak = Math.max(bestWinStreak, currentWinStreak);
    bestUnbeaten = Math.max(bestUnbeaten, currentUnbeaten);

    const goalRoll = random();
    const strengthGoalShift = winRate >= 0.85 ? 0.08 : winRate >= 0.7 ? 0.04 : 0;
    const goals = goalRoll < 0.08 - strengthGoalShift ? 0
      : goalRoll < 0.24 - strengthGoalShift ? 1
        : goalRoll < 0.47 ? 2 : goalRoll < 0.69 ? 3
          : goalRoll < 0.84 ? 4 : goalRoll < 0.94 ? 5 : 6;
    if (goals >= 2) {
      const goalRarity: Rarity = goals === 2 ? "common"
        : goals <= 4 ? "uncommon" : goals === 5 ? "rare" : "epic";
      openBox(goalRarity, `team.external.match_goals.${goals}`);
    }

    const scorerRoll = random();
    const goalsByPlayer = goals === 0 || scorerRoll < 0.42 ? 0
      : scorerRoll < 0.78 ? 1
        : scorerRoll < 0.94 ? Math.min(2, goals)
          : scorerRoll < 0.985 ? Math.min(3, goals)
            : Math.min(6, goals);
    const previousPlayerGoals = playerGoals;
    playerGoals += goalsByPlayer;
    if (goalsByPlayer >= 2) individualAchievements += 1;

    if (won) {
      const resultRoll = random();
      if (resultRoll < 0.18) openBox("uncommon", "team.external.big_wins.001");
      else if (resultRoll < 0.58) openBox("common", "team.external.close_wins.001");
    }
    const cleanSheetChance = 0.11 + (winRate - 0.5) * 0.16;
    if (random() < cleanSheetChance) {
      openBox("common", "team.external.clean_sheets.001");
    }

    oneTimeMilestone(match, matchMilestones, "team.external.matches");
    oneTimeMilestone(wins, winMilestones, "team.external.wins");
    oneTimeMilestone(bestWinStreak, winStreakMilestones, "team.external.win_streak");
    oneTimeMilestone(bestUnbeaten, unbeatenMilestones, "team.external.unbeaten");
    oneTimeMilestone(seenOpponents.size, opponentMilestones, "team.external.opponents_played");
    oneTimeMilestone(beatenOpponents.size, opponentWinMilestones, "team.external.opponents_won");
    individualMilestone(match, matchMilestones.map(([threshold]) => threshold), "player.matches");
    individualMilestone(wins, [1, ...winMilestones.map(([threshold]) => threshold)], "player.wins");
    individualMilestone(playerGoals, playerGoalMilestones, "player.goals", previousPlayerGoals);
    individualMilestone(bestWinStreak, winStreakMilestones.map(([threshold]) => threshold), "player.win_streak");
    individualMilestone(bestUnbeaten, unbeatenMilestones.map(([threshold]) => threshold), "player.unbeaten");
    individualMilestone(seenOpponents.size, opponentMilestones.map(([threshold]) => threshold), "player.opponents_played");
    individualMilestone(beatenOpponents.size, opponentWinMilestones.map(([threshold]) => threshold), "player.opponents_won");
    boxesPerMatch.push(boxes - boxesBefore);
  }

  return { boxes, boxesPerMatch, cosmetics: owned.size, duplicates, individualAchievements, matches, points };
}

export function rewardEconomyScenarios(iterations = 160): EconomySimulationSummary[] {
  const weeklyProfiles = [1, 2, 4] as const;
  const periods = [3, 6, 12] as const;
  const strengths = [0.5, 0.7, 0.85] as const;
  return weeklyProfiles.flatMap((weeklyMatches) => periods.flatMap((months) => strengths.map((winRate) => {
    const seasons = Array.from({ length: iterations }, (_, iteration) => simulateSeason(
      weeklyMatches, months, winRate,
      0x51a7 + weeklyMatches * 10_000 + months * 100 + Math.round(winRate * 100) + iteration,
    ));
    const allMatches = seasons.flatMap((season) => season.boxesPerMatch);
    return {
      averageBoxesPerMatch: rounded(seasons.reduce((sum, season) => sum + season.boxes, 0)
        / seasons.reduce((sum, season) => sum + season.matches, 0)),
      averageBoxesPerSeason: rounded(seasons.reduce((sum, season) => sum + season.boxes, 0) / iterations),
      averageCollectiveAchievements: rounded(seasons.reduce((sum, season) => sum + season.boxes, 0) / iterations),
      averageCosmetics: rounded(seasons.reduce((sum, season) => sum + season.cosmetics, 0) / iterations),
      averageDuplicates: rounded(seasons.reduce((sum, season) => sum + season.duplicates, 0) / iterations),
      averageIndividualAchievements: rounded(seasons.reduce(
        (sum, season) => sum + season.individualAchievements, 0,
      ) / iterations),
      averagePoints: rounded(seasons.reduce((sum, season) => sum + season.points, 0) / iterations),
      matches: seasons[0]!.matches,
      maxBoxesPerMatch: Math.max(...allMatches),
      months,
      p50BoxesPerMatch: percentile(allMatches, 0.5),
      p90BoxesPerMatch: percentile(allMatches, 0.9),
      weeklyMatches,
      winRate,
    };
  })));
}

test("the definitive catalog remains rewarding without routine box inflation", () => {
  const scenarios = rewardEconomyScenarios();
  assert.equal(scenarios.length, 27);
  for (const scenario of scenarios) {
    // Early seasons intentionally cluster first-time awards and low milestones.
    assert.ok(scenario.averageBoxesPerMatch <= 3.4, JSON.stringify(scenario));
    assert.ok(scenario.p90BoxesPerMatch <= 6, JSON.stringify(scenario));
    assert.ok(scenario.maxBoxesPerMatch <= 10, JSON.stringify(scenario));
  }
  for (const annualScenario of scenarios.filter((scenario) => scenario.months === 12)) {
    assert.ok(annualScenario.averageBoxesPerMatch < 2.8, JSON.stringify(annualScenario));
    assert.ok(annualScenario.p90BoxesPerMatch <= 4, JSON.stringify(annualScenario));
  }
  const annualVeryActiveStrong = scenarios.find((scenario) => (
    scenario.weeklyMatches === 4 && scenario.months === 12 && scenario.winRate === 0.85
  ))!;
  assert.ok(annualVeryActiveStrong.averageBoxesPerSeason < 800, JSON.stringify(annualVeryActiveStrong));
  assert.ok(annualVeryActiveStrong.averagePoints < 12_000, JSON.stringify(annualVeryActiveStrong));
  assert.ok(annualVeryActiveStrong.averageCosmetics <= 12);
});

test("winning more raises rewards gradually instead of multiplying them", () => {
  const annualActive = rewardEconomyScenarios().filter((scenario) => (
    scenario.weeklyMatches === 2 && scenario.months === 12
  ));
  assert.deepEqual(annualActive.map((scenario) => scenario.winRate), [0.5, 0.7, 0.85]);
  assert.ok(annualActive[0]!.averageBoxesPerSeason < annualActive[1]!.averageBoxesPerSeason);
  assert.ok(annualActive[1]!.averageBoxesPerSeason < annualActive[2]!.averageBoxesPerSeason);
  assert.ok(annualActive[2]!.averageBoxesPerSeason / annualActive[0]!.averageBoxesPerSeason < 1.7);
});

test("every simulated reward remains cosmetic and separate from Rating V2", () => {
  for (const entries of Object.values(pools)) {
    for (const entry of entries) {
      assert.ok(["points", "player_cosmetic", "combination"].includes(entry.kind));
      assert.equal("rating" in entry, false);
      assert.equal("facets" in entry, false);
    }
  }
});

test("individual recognition is measured but never added to the reward count", () => {
  for (const scenario of rewardEconomyScenarios()) {
    assert.ok(scenario.averageIndividualAchievements > 0);
    assert.equal(scenario.averageCollectiveAchievements, scenario.averageBoxesPerSeason);
  }
});

if (process.env.ACHIEVEMENT_SIMULATION_REPORT === "1") {
  process.stdout.write(`${JSON.stringify(rewardEconomyScenarios(), null, 2)}\n`);
}
