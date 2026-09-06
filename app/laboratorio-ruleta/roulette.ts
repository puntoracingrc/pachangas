export const odds = [60, 25, 10, 4, 1] as const;
export function pickRarity(value: number, weights: readonly number[] = odds) {
  if (!Number.isFinite(value) || value < 0 || value >= 1) throw new Error("Expected a random value in [0, 1)");
  let cumulative = 0;
  for (let i = 0; i < weights.length; i++) {
    cumulative += weights[i];
    if (value * 100 < cumulative) return i;
  }
  return 4;
}
export function createStrip(random: () => number, confirmedWinner?: number, weights: readonly number[] = odds) {
  const winner = confirmedWinner ?? pickRarity(random(), weights);
  const strip = Array.from({ length: 48 }, () => pickRarity(random(), weights));
  // Independent landing point: never changes the prize or rigs adjacent rarities.
  const landing = 0.06 + random() * 0.88;
  strip[tileAtPosition(40 + landing)] = winner;
  return { winner, strip, landing };
}

export type Loot = { key: string | null; points: number; duplicate: boolean };

// Continuous, adjoining cells: [i, i + 1). A boundary belongs to the right cell.
export function tileAtPosition(position: number) {
  if (!Number.isFinite(position) || position < 0 || position >= 48) throw new Error("Position outside roulette");
  return Math.floor(position);
}

