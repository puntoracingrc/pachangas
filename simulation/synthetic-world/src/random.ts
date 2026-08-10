import { createHash } from "node:crypto";

export class SeededRandom {
  private state: number;

  constructor(seed: number | string) {
    const normalized = typeof seed === "number" ? seed : Number.parseInt(createHash("sha256").update(seed).digest("hex").slice(0, 8), 16);
    this.state = normalized >>> 0 || 0x6d2b79f5;
  }

  next() {
    this.state += 0x6d2b79f5;
    let value = this.state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  }

  bool(probability = 0.5) {
    return this.next() < probability;
  }

  integer(minimum: number, maximum: number) {
    return minimum + Math.floor(this.next() * (maximum - minimum + 1));
  }

  decimal(minimum: number, maximum: number) {
    return minimum + this.next() * (maximum - minimum);
  }

  fork(label: string) {
    return new SeededRandom(`${label}:${this.integer(0, 0xffff_ffff)}`);
  }

  pick<T>(values: readonly T[]): T {
    if (values.length === 0) throw new Error("Cannot pick from an empty collection");
    return values[Math.min(values.length - 1, Math.floor(this.next() * values.length))]!;
  }

  weighted<T>(values: ReadonlyArray<{ value: T; weight: number }>): T {
    const total = values.reduce((sum, item) => sum + item.weight, 0);
    let target = this.next() * total;
    for (const item of values) {
      target -= item.weight;
      if (target <= 0) return item.value;
    }
    return values.at(-1)!.value;
  }

  sample<T>(values: readonly T[], count: number) {
    const copy = [...values];
    for (let index = copy.length - 1; index > 0; index -= 1) {
      const swap = this.integer(0, index);
      [copy[index], copy[swap]] = [copy[swap]!, copy[index]!];
    }
    return copy.slice(0, Math.max(0, count));
  }
}

export function deterministicUuid(namespace: string, value: string | number) {
  const hex = createHash("sha256").update(`${namespace}:${value}`).digest("hex").slice(0, 32).split("");
  hex[12] = "4";
  hex[16] = ((Number.parseInt(hex[16]!, 16) & 0x3) | 0x8).toString(16);
  const compact = hex.join("");
  return `${compact.slice(0, 8)}-${compact.slice(8, 12)}-${compact.slice(12, 16)}-${compact.slice(16, 20)}-${compact.slice(20)}`;
}

export function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}
