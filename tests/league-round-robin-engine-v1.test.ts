import assert from "node:assert/strict";
import test from "node:test";
import {
  generateLeagueRoundRobin,
  validateLeagueRoundRobin,
} from "../app/league-round-robin-engine";

function entries(count: number) {
  return Array.from({ length: count }, (_, index) => `entry-${String(index + 1).padStart(2, "0")}`);
}

test("one-leg round robin is complete and balanced for every supported capacity", () => {
  for (let count = 2; count <= 32; count += 1) {
    const schedule = generateLeagueRoundRobin(entries(count), { legs: 1, seed: "capacity-regression" });
    const validation = validateLeagueRoundRobin(schedule);
    assert.equal(validation.fixtureCount, count * (count - 1) / 2, `fixtures for ${count}`);
    assert.equal(validation.roundCount, count % 2 === 0 ? count - 1 : count, `rounds for ${count}`);
    assert.equal(validation.duplicatePairings, 0, `pairings for ${count}`);
    assert.ok(validation.balanceMaximum <= 1, `home/away balance for ${count}`);
    assert.equal(validation.byeCount, count % 2 === 0 ? 0 : count, `byes for ${count}`);
    if (count % 2 === 1) {
      assert.deepEqual(new Set(Object.values(validation.byesPerEntry)), new Set([1]));
    }
  }
});

test("second leg is a deterministic home-away mirror", () => {
  for (const count of [2, 5, 6, 20, 32]) {
    const schedule = generateLeagueRoundRobin(entries(count), { legs: 2, seed: `mirror-${count}` });
    const validation = validateLeagueRoundRobin(schedule);
    assert.equal(validation.fixtureCount, count * (count - 1));
    assert.equal(validation.mirrorValid, true);
    assert.equal(validation.balanceMaximum, 0);
    assert.equal(validation.byeCount, count % 2 === 0 ? 0 : count * 2);
  }
});

test("maximum supported league produces 62 rounds and 992 fixtures", () => {
  const schedule = generateLeagueRoundRobin(entries(32), { legs: 2, seed: "capacity-32" });
  const validation = validateLeagueRoundRobin(schedule);
  assert.equal(validation.roundCount, 62);
  assert.equal(validation.fixtureCount, 992);
  assert.equal(validation.duplicatePairings, 0);
  assert.equal(validation.mirrorValid, true);
});

test("five and six-team reference stories match the R4B contract", () => {
  const five = validateLeagueRoundRobin(generateLeagueRoundRobin(entries(5), { legs: 1, seed: "five" }));
  assert.deepEqual({ byes: five.byeCount, fixtures: five.fixtureCount, rounds: five.roundCount }, {
    byes: 5,
    fixtures: 10,
    rounds: 5,
  });
  const six = validateLeagueRoundRobin(generateLeagueRoundRobin(entries(6), { legs: 1, seed: "six" }));
  assert.deepEqual({ byes: six.byeCount, fixtures: six.fixtureCount, rounds: six.roundCount }, {
    byes: 0,
    fixtures: 15,
    rounds: 5,
  });
});

test("generation is reproducible and a persisted seed may change order", () => {
  const source = entries(12);
  const first = generateLeagueRoundRobin(source, { legs: 2, seed: "same-seed" });
  const replay = generateLeagueRoundRobin([...source].reverse(), { legs: 2, seed: "same-seed" });
  const changed = generateLeagueRoundRobin(source, { legs: 2, seed: "different-seed" });
  assert.deepEqual(replay, first);
  assert.notEqual(changed.signature, first.signature);
  assert.notDeepEqual(changed.entryOrder, first.entryOrder);
});

test("engine fails closed outside 2-32 entries and rejects duplicates", () => {
  assert.throws(() => generateLeagueRoundRobin(entries(1), { legs: 1, seed: "seed" }), /AT_LEAST_TWO/);
  assert.throws(() => generateLeagueRoundRobin(entries(33), { legs: 1, seed: "seed" }), /CAPACITY_EXCEEDED/);
  assert.throws(() => generateLeagueRoundRobin(["a", "a"], { legs: 1, seed: "seed" }), /ENTRY_SET_INVALID/);
  assert.throws(() => generateLeagueRoundRobin(["a", "b"], { legs: 1, seed: "" }), /SEED_INVALID/);
});
