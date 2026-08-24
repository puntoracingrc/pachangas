import { generateLeagueRoundRobin, validateLeagueRoundRobin } from "../league-round-robin-engine";
import type { LeagueSchedulingJson } from "../league-scheduling-contract";

export const leagueSchedulingScenarios = [
  ["four", "4 equipos"],
  ["five", "5 equipos y descansos"],
  ["six", "6 equipos"],
  ["double", "Doble vuelta"],
  ["conflict", "Conflicto duro"],
  ["preferences", "Preferencias"],
  ["draft", "Borrador"],
  ["validated", "Validado"],
  ["published", "Publicado"],
] as const;

export type LeagueSchedulingScenario = typeof leagueSchedulingScenarios[number][0];

const teamNames = [
  "Cobalto Real",
  "Vértice Gràcia",
  "Carboni Terrassa",
  "Atlético Levant",
  "Nexo Sabadell",
  "Distrito Norte",
];

function scenarioOptions(scenario: LeagueSchedulingScenario) {
  if (scenario === "four") return { count: 4, legs: 1 as const };
  if (scenario === "five") return { count: 5, legs: 1 as const };
  if (scenario === "double") return { count: 6, legs: 2 as const };
  return { count: 6, legs: 1 as const };
}

function statusFor(scenario: LeagueSchedulingScenario) {
  if (scenario === "draft") return "draft";
  if (scenario === "validated") return "validated";
  if (scenario === "published") return "published";
  return "generated";
}

function at(roundIndex: number, fixtureIndex: number) {
  const value = new Date(Date.UTC(2027, 1, 6 + roundIndex * 7, 17 + fixtureIndex * 2));
  return value.toISOString();
}

export function leagueSchedulingFixture(scenario: LeagueSchedulingScenario): LeagueSchedulingJson {
  const { count, legs } = scenarioOptions(scenario);
  const entryIds = Array.from({ length: count }, (_, index) => `entry-${index + 1}`);
  const schedule = generateLeagueRoundRobin(entryIds, { legs, seed: `laboratorio-${scenario}` });
  const validation = validateLeagueRoundRobin(schedule);
  const planStatus = statusFor(scenario);
  const rounds = scenario === "draft" ? [] : schedule.rounds.map((round) => ({
    endsAt: at(round.roundNumber - 1, Math.max(round.fixtures.length - 1, 0)),
    id: `round-${round.roundNumber}`,
    leg: round.legNumber,
    name: `Jornada ${round.roundNumber}`,
    number: round.roundNumber,
    startsAt: at(round.roundNumber - 1, 0),
    status: planStatus === "published" ? "published" : "draft",
  }));
  const items = scenario === "draft" ? [] : schedule.rounds.flatMap((round) => round.fixtures.map((fixture, fixtureIndex) => ({
    awayEntryId: fixture.awayEntryId,
    awayTeam: teamNames[entryIds.indexOf(fixture.awayEntryId)],
    endsAt: new Date(new Date(at(round.roundNumber - 1, fixtureIndex)).getTime() + 90 * 60_000).toISOString(),
    homeEntryId: fixture.homeEntryId,
    homeTeam: teamNames[entryIds.indexOf(fixture.homeEntryId)],
    id: `item-${round.roundNumber}-${fixtureIndex + 1}`,
    leg: round.legNumber,
    roundId: `round-${round.roundNumber}`,
    roundNumber: round.roundNumber,
    slotId: `slot-${round.roundNumber}-${fixtureIndex + 1}`,
    startsAt: at(round.roundNumber - 1, fixtureIndex),
    status: scenario === "conflict" && round.roundNumber === 1 && fixtureIndex === 0
      ? "conflicted"
      : planStatus === "published" ? "published" : planStatus === "validated" ? "validated" : "assigned",
    timezone: "Europe/Madrid",
    venueLabel: fixtureIndex % 2 ? "Sede pendiente" : "Campo Municipal Nord",
    venueStatus: fixtureIndex % 2 ? "TBD" : "CONFIRMED",
  })));
  const conflicts = scenario === "conflict" ? [{
    detail: "Cobalto Real no está disponible en la franja asignada.",
    id: "conflict-team-unavailable",
    type: "TEAM_UNAVAILABLE",
  }] : [];
  const preferenceTotal = items.length * 2;
  const preferenceSatisfied = scenario === "preferences" ? Math.max(preferenceTotal - 3, 0) : preferenceTotal;
  const softScore = scenario === "preferences" ? 86.5 : conflicts.length ? 58 : planStatus === "draft" ? 0 : 96;
  return {
    competition: { id: "competition-lab", name: "Liga Metropolitana Demo" },
    conflicts,
    counts: { byes: validation.byeCount, items: items.length, rounds: rounds.length },
    diff: {},
    engine: { capacity: 32, signature: schedule.signature, version: schedule.engineVersion },
    items,
    nextValidActions: planStatus === "draft"
      ? ["schedule_slot.bulk_create", "schedule.generate", "schedule.cancel"]
      : planStatus === "generated"
        ? ["schedule.regenerate", "schedule_item.move_slot", "schedule_item.swap_home_away", "schedule.validate", "schedule.cancel"]
        : planStatus === "validated" ? ["schedule.publish", "schedule.regenerate", "schedule.cancel"] : [],
    plan: { id: `plan-${scenario}`, revision: 8, status: planStatus },
    quality: {
      explanation: { preferences: { satisfied: preferenceSatisfied, total: preferenceTotal } },
      hardViolations: conflicts.length,
      maximumAwayStreak: 2,
      maximumHomeStreak: 2,
      softScore,
    },
    revision: { id: `revision-${scenario}`, seed: schedule.seed, status: planStatus, version: 3 },
    rounds,
    slots: items.map((item, index) => ({
      endsAt: item.endsAt,
      id: item.slotId,
      resourceKey: `campo-${index % 3 + 1}`,
      startsAt: item.startsAt,
      status: index < 3 ? "available" : "assigned",
      timezone: "Europe/Madrid",
      venueLabel: item.venueLabel,
    })),
  };
}
