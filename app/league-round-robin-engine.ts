import {
  leagueSchedulingEngineVersion,
  leagueSchedulingMaximumEntries,
  leagueSchedulingMinimumEntries,
} from "./league-scheduling-contract";

export type LeaguePairing = {
  awayEntryId: string;
  homeEntryId: string;
  legNumber: 1 | 2;
  pairingKey: string;
  roundNumber: number;
};

export type LeagueRound = {
  byeEntryId: string | null;
  fixtures: LeaguePairing[];
  legNumber: 1 | 2;
  roundNumber: number;
};

export type LeagueRoundRobinSchedule = {
  engineVersion: typeof leagueSchedulingEngineVersion;
  entryOrder: string[];
  legs: 1 | 2;
  rounds: LeagueRound[];
  seed: string;
  signature: string;
};

function hash32(value: string) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function pairKey(left: string, right: string) {
  return left < right ? `${left}:${right}` : `${right}:${left}`;
}

function seededOrder(entryIds: readonly string[], seed: string) {
  return [...entryIds].sort((left, right) => {
    const hashDifference = hash32(`${seed}:${left}`) - hash32(`${seed}:${right}`);
    return hashDifference || left.localeCompare(right);
  });
}

function balanceOddFirstLeg(rounds: LeagueRound[], entryIds: readonly string[]) {
  const balance = new Map(entryIds.map((entryId) => [entryId, 0]));
  for (const round of rounds) for (const fixture of round.fixtures) {
    balance.set(fixture.homeEntryId, (balance.get(fixture.homeEntryId) ?? 0) + 1);
    balance.set(fixture.awayEntryId, (balance.get(fixture.awayEntryId) ?? 0) - 1);
  }
  for (;;) {
    const candidate = rounds.flatMap((round) => round.fixtures).find((fixture) => (
      (balance.get(fixture.homeEntryId) ?? 0) > 1
      && (balance.get(fixture.awayEntryId) ?? 0) < -1
    ));
    if (!candidate) break;
    const previousHome = candidate.homeEntryId;
    candidate.homeEntryId = candidate.awayEntryId;
    candidate.awayEntryId = previousHome;
    balance.set(candidate.homeEntryId, (balance.get(candidate.homeEntryId) ?? 0) + 2);
    balance.set(candidate.awayEntryId, (balance.get(candidate.awayEntryId) ?? 0) - 2);
  }
}

function scheduleSignature(rounds: readonly LeagueRound[], seed: string) {
  const source = rounds.map((round) => [
    round.roundNumber,
    round.legNumber,
    round.byeEntryId,
    round.fixtures.map((fixture) => [fixture.homeEntryId, fixture.awayEntryId]),
  ]);
  return hash32(`${leagueSchedulingEngineVersion}:${seed}:${JSON.stringify(source)}`)
    .toString(16)
    .padStart(8, "0");
}

export function generateLeagueRoundRobin(
  rawEntryIds: readonly string[],
  options: { legs: 1 | 2; seed: string },
): LeagueRoundRobinSchedule {
  const uniqueEntries = [...new Set(rawEntryIds.map((value) => value.trim()).filter(Boolean))];
  if (uniqueEntries.length !== rawEntryIds.length) throw new Error("SCHEDULE_ENTRY_SET_INVALID");
  if (uniqueEntries.length < leagueSchedulingMinimumEntries) throw new Error("SCHEDULE_REQUIRES_AT_LEAST_TWO_ENTRIES");
  if (uniqueEntries.length > leagueSchedulingMaximumEntries) throw new Error("SCHEDULE_ENGINE_CAPACITY_EXCEEDED");
  if (![1, 2].includes(options.legs)) throw new Error("SCHEDULE_LEGS_INVALID");
  const seed = options.seed.trim();
  if (!seed || seed.length > 160) throw new Error("SCHEDULE_SEED_INVALID");

  const entryOrder = seededOrder(uniqueEntries, seed);
  const rotation: Array<string | null> = [...entryOrder];
  if (rotation.length % 2 === 1) rotation.push(null);
  const roundsPerLeg = rotation.length - 1;
  const firstLeg: LeagueRound[] = [];

  for (let roundIndex = 0; roundIndex < roundsPerLeg; roundIndex += 1) {
    const fixtures: LeaguePairing[] = [];
    let byeEntryId: string | null = null;
    for (let pairIndex = 0; pairIndex < rotation.length / 2; pairIndex += 1) {
      const left = rotation[pairIndex];
      const right = rotation[rotation.length - pairIndex - 1];
      if (!left || !right) {
        byeEntryId = left ?? right;
        continue;
      }
      const swap = pairIndex === 0 ? roundIndex % 2 === 1 : pairIndex % 2 === 1;
      const homeEntryId = swap ? right : left;
      const awayEntryId = swap ? left : right;
      fixtures.push({
        awayEntryId,
        homeEntryId,
        legNumber: 1,
        pairingKey: pairKey(homeEntryId, awayEntryId),
        roundNumber: roundIndex + 1,
      });
    }
    firstLeg.push({ byeEntryId, fixtures, legNumber: 1, roundNumber: roundIndex + 1 });
    rotation.splice(1, 0, rotation.pop() ?? null);
  }

  if (entryOrder.length % 2 === 1) balanceOddFirstLeg(firstLeg, entryOrder);
  const rounds = [...firstLeg];
  if (options.legs === 2) {
    for (const sourceRound of firstLeg) {
      const roundNumber = roundsPerLeg + sourceRound.roundNumber;
      rounds.push({
        byeEntryId: sourceRound.byeEntryId,
        fixtures: sourceRound.fixtures.map((fixture) => ({
          awayEntryId: fixture.homeEntryId,
          homeEntryId: fixture.awayEntryId,
          legNumber: 2,
          pairingKey: fixture.pairingKey,
          roundNumber,
        })),
        legNumber: 2,
        roundNumber,
      });
    }
  }

  return {
    engineVersion: leagueSchedulingEngineVersion,
    entryOrder,
    legs: options.legs,
    rounds,
    seed,
    signature: scheduleSignature(rounds, seed),
  };
}

export function validateLeagueRoundRobin(schedule: LeagueRoundRobinSchedule) {
  const fixtureList = schedule.rounds.flatMap((round) => round.fixtures);
  const entries = schedule.entryOrder;
  const expectedPerLeg = entries.length * (entries.length - 1) / 2;
  const pairCounts = new Map<string, number>();
  const balances = new Map(entries.map((entryId) => [entryId, { away: 0, home: 0 }]));
  const byes = new Map(entries.map((entryId) => [entryId, 0]));
  for (const round of schedule.rounds) {
    if (round.byeEntryId) byes.set(round.byeEntryId, (byes.get(round.byeEntryId) ?? 0) + 1);
    const roundEntries = new Set<string>();
    for (const fixture of round.fixtures) {
      if (roundEntries.has(fixture.homeEntryId) || roundEntries.has(fixture.awayEntryId)) {
        throw new Error("SCHEDULE_TEAM_DUPLICATED_IN_ROUND");
      }
      roundEntries.add(fixture.homeEntryId);
      roundEntries.add(fixture.awayEntryId);
      pairCounts.set(`${fixture.legNumber}:${fixture.pairingKey}`, (pairCounts.get(`${fixture.legNumber}:${fixture.pairingKey}`) ?? 0) + 1);
      const home = balances.get(fixture.homeEntryId);
      const away = balances.get(fixture.awayEntryId);
      if (!home || !away) throw new Error("SCHEDULE_UNKNOWN_ENTRY");
      home.home += 1;
      away.away += 1;
    }
  }
  const mirrorValid = schedule.legs === 1 || fixtureList.filter((fixture) => fixture.legNumber === 1).every((first) => (
    fixtureList.some((second) => second.legNumber === 2
      && second.pairingKey === first.pairingKey
      && second.homeEntryId === first.awayEntryId
      && second.awayEntryId === first.homeEntryId)
  ));
  return {
    balanceMaximum: Math.max(...[...balances.values()].map(({ away, home }) => Math.abs(home - away))),
    byeCount: [...byes.values()].reduce((total, count) => total + count, 0),
    byesPerEntry: Object.fromEntries(byes),
    duplicatePairings: [...pairCounts.values()].filter((count) => count !== 1).length,
    expectedFixtures: expectedPerLeg * schedule.legs,
    fixtureCount: fixtureList.length,
    mirrorValid,
    roundCount: schedule.rounds.length,
  };
}
