export class DeterministicRandom {
  private spareNormal: number | null = null;
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  bool(probability: number) {
    return this.next() < probability;
  }

  integer(minimum: number, maximum: number) {
    return minimum + Math.floor(this.next() * (maximum - minimum + 1));
  }

  normal(mean = 0, standardDeviation = 1) {
    if (this.spareNormal !== null) {
      const spare = this.spareNormal;
      this.spareNormal = null;
      return mean + spare * standardDeviation;
    }
    const first = Math.max(Number.EPSILON, this.next());
    const second = this.next();
    const magnitude = Math.sqrt(-2 * Math.log(first));
    const angle = 2 * Math.PI * second;
    this.spareNormal = magnitude * Math.sin(angle);
    return mean + magnitude * Math.cos(angle) * standardDeviation;
  }

  next() {
    this.state = (Math.imul(this.state, 1664525) + 1013904223) >>> 0;
    return this.state / 0x1_0000_0000;
  }

  pick<T>(values: readonly T[]) {
    if (values.length === 0) throw new Error("Cannot pick from an empty collection");
    return values[Math.floor(this.next() * values.length)]!;
  }

  weightedPick<T>(values: readonly T[], weights: readonly number[]) {
    if (values.length === 0 || values.length !== weights.length) {
      throw new Error("Weighted values and weights must be non-empty and aligned");
    }
    const total = weights.reduce((sum, value) => sum + value, 0);
    let cursor = this.next() * total;
    for (let index = 0; index < values.length; index += 1) {
      cursor -= weights[index]!;
      if (cursor <= 0) return values[index]!;
    }
    return values.at(-1)!;
  }
}

export function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}

export function round(value: number, digits = 2) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}
