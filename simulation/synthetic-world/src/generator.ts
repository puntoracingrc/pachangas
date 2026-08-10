import { DEFAULT_WORLD_CONFIG, DEFAULT_WORLD_START, PROVINCE_WEIGHTS, SYNTHETIC_PROVINCES, SYNTHETIC_SOURCE_COMMIT } from "./config";
import { CANONICAL_CONTRACTS } from "./canonical-contracts";
import { knownIncidentsForWorld } from "./known-incidents";
import { clamp, deterministicUuid, SeededRandom } from "./random";
import type {
  SyntheticAgent,
  SyntheticAttackProfile,
  SyntheticAttendanceProfile,
  SyntheticConductProfile,
  SyntheticCoverage,
  SyntheticIncident,
  SyntheticModality,
  SyntheticPersona,
  SyntheticTeam,
  SyntheticVenue,
  SyntheticWorld,
  SyntheticWorldConfig,
  SyntheticWorldMode,
} from "./types";

const firstNames = [
  "Alex", "Alma", "Bruno", "Carla", "Dani", "Eric", "Eva", "Hugo", "Irene", "Joel",
  "Leo", "Lina", "Marc", "Marta", "Nico", "Noa", "Pablo", "Paula", "Rai", "Sara",
  "Sergio", "Sofía", "Uri", "Vera", "Víctor",
];
const surnameInitials = ["A.", "B.", "C.", "D.", "F.", "G.", "L.", "M.", "N.", "P.", "R.", "S.", "T.", "V."];
const teamRoots = [
  "Raval", "Norte", "Levante", "Triana", "Vallès", "Arganzuela", "Turia", "Macarena", "Montjuïc", "Retiro",
  "Sants", "Malvarrosa", "Eixample", "Nervión", "Gràcia", "Chamartín", "Campanar", "Heliópolis", "Besòs", "Moncloa",
  "Clot", "Patraix", "Poble-sec", "Carabanchel", "Sant Andreu",
];
const teamSuffixes = ["Athletic", "City", "FC", "United", "Club", "Pachanga"];
const personas: Array<{ value: SyntheticPersona; weight: number }> = [
  { value: "regular", weight: 24 }, { value: "casual", weight: 15 }, { value: "competitive", weight: 11 },
  { value: "social", weight: 9 }, { value: "loyal", weight: 8 }, { value: "slow_responder", weight: 7 },
  { value: "low_activity", weight: 6 }, { value: "newcomer", weight: 5 }, { value: "multi_team", weight: 4 },
  { value: "unreliable", weight: 3 }, { value: "hyperactive", weight: 3 }, { value: "mercenary", weight: 2 },
  { value: "returning", weight: 2 }, { value: "dormant", weight: 1 },
];
const attackProfiles: SyntheticAttackProfile[] = [
  "opponent_farmer", "colluder", "ghost_participant", "team_hopper", "territory_gamer",
  "fake_team_operator", "sybil_operator", "rating_manipulator",
];
const attendanceProfiles: Array<{ value: SyntheticAttendanceProfile; weight: number }> = [
  { value: "normal", weight: 51 }, { value: "correct_rejector", weight: 10 },
  { value: "early_canceller", weight: 10 }, { value: "late_canceller", weight: 9 },
  { value: "occasional_no_show", weight: 6 }, { value: "repeat_no_show", weight: 3 },
  { value: "stops_responding", weight: 6 }, { value: "injury_prone", weight: 5 },
];
const conductProfiles: Array<{ value: SyntheticConductProfile; weight: number }> = [
  { value: "fair", weight: 83 }, { value: "occasional_unsporting", weight: 8 },
  { value: "conflict_prone", weight: 4 }, { value: "repeat_offender", weight: 2 },
  { value: "coordinated_false_reporter", weight: 2 }, { value: "retaliatory", weight: 1 },
];
const positions = ["POR", "DEF", "MC", "DEL"] as const;
const modalities: Array<{ value: SyntheticModality; weight: number }> = [
  { value: "sala", weight: 35 }, { value: "futbol7", weight: 50 }, { value: "futbol11", weight: 15 },
];

function personaBehavior(persona: SyntheticPersona, random: SeededRandom) {
  const defaults = { acceptance: 0.68, marketAffinity: 0.2, notificationDelayHours: 5, reliability: 0.83, socialAffinity: 0.55 };
  const behaviorOverrides: Partial<Record<SyntheticPersona, Partial<typeof defaults>>> = {
    casual: { acceptance: 0.46, reliability: 0.72 },
    competitive: { acceptance: 0.78, reliability: 0.92 },
    dormant: { acceptance: 0.08, notificationDelayHours: 168, reliability: 0.35 },
    hyperactive: { acceptance: 0.94, notificationDelayHours: 0.2, reliability: 0.89 },
    loyal: { acceptance: 0.8, marketAffinity: 0.02, reliability: 0.95 },
    low_activity: { acceptance: 0.25, notificationDelayHours: 30 },
    mercenary: { acceptance: 0.72, marketAffinity: 0.92, socialAffinity: 0.32 },
    multi_team: { acceptance: 0.74, marketAffinity: 0.68 },
    newcomer: { acceptance: 0.64, marketAffinity: 0.74, reliability: 0.69 },
    returning: { acceptance: 0.58, notificationDelayHours: 18 },
    slow_responder: { acceptance: 0.62, notificationDelayHours: 28 },
    social: { acceptance: 0.82, socialAffinity: 0.96 },
    unreliable: { acceptance: 0.7, reliability: 0.35 },
  };
  const overrides = behaviorOverrides[persona] ?? {};
  return {
    ...defaults,
    ...overrides,
    acceptance: clamp((overrides.acceptance ?? defaults.acceptance) + random.decimal(-0.08, 0.08), 0.02, 0.98),
    notificationDelayHours: Math.max(0, (overrides.notificationDelayHours ?? defaults.notificationDelayHours) + random.decimal(-2, 4)),
  };
}

function generatedFacets(rating: number, random: SeededRandom) {
  const facet = () => Math.round(clamp(rating + random.decimal(-13, 13), 20, 98));
  return { defensa: facet(), fisico: facet(), pase: facet(), regate: facet(), ritmo: facet(), tiro: facet() };
}

function createAgents(seed: number, config: SyntheticWorldConfig) {
  const random = new SeededRandom(`${seed}:agents`);
  const total = config.agentCount + config.guestCount;
  return Array.from({ length: total }, (_, index): SyntheticAgent => {
    const registered = index < config.agentCount;
    const persona = registered ? random.weighted(personas) : "casual";
    const province = random.weighted(PROVINCE_WEIGHTS);
    const ratingV2 = Math.round(clamp(random.decimal(45, 88) + (persona === "competitive" ? 6 : 0), 35, 96) * 10) / 10;
    const futureOffsetDays = persona === "newcomer" || index > total * 0.9 ? random.integer(5, 150) : 0;
    const attackProfile = registered && random.bool(config.attackRate) ? random.pick(attackProfiles) : "none";
    const id = `${registered ? "agent" : "guest"}-${String(index + 1).padStart(3, "0")}`;
    const unavailable = registered && random.bool(0.035);
    return {
      attackProfile,
      attendanceProfile: registered ? random.weighted(attendanceProfiles) : "normal",
      availableFrom: new Date(Date.parse(DEFAULT_WORLD_START) + futureOffsetDays * 86_400_000).toISOString(),
      behavior: personaBehavior(persona, random),
      city: province.city,
      conductProfile: registered ? random.weighted(conductProfiles) : "fair",
      displayName: `SIM · ${random.pick(firstNames)} ${random.pick(surnameInitials)} ${String(index + 1).padStart(3, "0")}`,
      facets: generatedFacets(ratingV2, random),
      id,
      kind: registered ? "registered" : "guest",
      notificationPreferences: {
        achievement: { email: false, inApp: random.bool(0.86), push: random.bool(0.28) },
        challenge: { email: false, inApp: random.bool(0.93), push: random.bool(0.42) },
        group: { email: false, inApp: random.bool(0.78), push: random.bool(0.2) },
        market: { email: false, inApp: random.bool(0.74), push: random.bool(0.18) },
        match: { email: false, inApp: random.bool(0.9), push: random.bool(0.38) },
        security: { email: false, inApp: random.bool(0.55), push: random.bool(0.25) },
      },
      persona,
      position: random.weighted([
        { value: positions[0], weight: 10 }, { value: positions[1], weight: 31 },
        { value: positions[2], weight: 34 }, { value: positions[3], weight: 25 },
      ]),
      productUserId: null,
      provinceCode: province.code,
      ratingReliability: Math.round(clamp(random.decimal(0.36, 0.94) + (persona === "newcomer" ? -0.18 : 0), 0.15, 0.99) * 100) / 100,
      ratingV2,
      status: futureOffsetDays > 0 ? "future" : unavailable ? "unavailable" : persona === "dormant" ? "dormant" : "active",
      teamIds: [],
      unavailableReason: unavailable ? "synthetic_injury" : null,
      unavailableUntil: unavailable
        ? new Date(Date.parse(DEFAULT_WORLD_START) + random.integer(14, 70) * 86_400_000).toISOString()
        : null,
    };
  });
}

function teamName(index: number) {
  return `SIM · ${teamRoots[index % teamRoots.length]} ${teamSuffixes[Math.floor(index / teamRoots.length) % teamSuffixes.length]}`;
}

function targetRoster(modality: SyntheticModality, random: SeededRandom) {
  if (modality === "sala") return random.integer(9, 12);
  if (modality === "futbol11") return random.integer(20, 24);
  return random.integer(13, 17);
}

function createTeams(seed: number, agents: SyntheticAgent[], config: SyntheticWorldConfig) {
  const random = new SeededRandom(`${seed}:teams`);
  const registered = agents.filter(({ kind }) => kind === "registered");
  const protectedFree = new Set(random.sample(registered, config.initialFreeAgentCount).map(({ id }) => id));
  const ownerPool = registered.filter((agent) => !protectedFree.has(agent.id));
  const teams: SyntheticTeam[] = [];

  for (let index = 0; index < config.teamCount; index += 1) {
    const province = random.weighted(PROVINCE_WEIGHTS);
    const modality = random.weighted(modalities);
    const rosterTarget = targetRoster(modality, random);
    const localOwners = ownerPool.filter((agent) => agent.provinceCode === province.code && agent.teamIds.length === 0);
    const owner = random.pick(localOwners.length > 0 ? localOwners : ownerPool.filter((agent) => agent.teamIds.length === 0));
    const teamId = `team-${String(index + 1).padStart(2, "0")}`;
    owner.teamIds.push(teamId);
    const roster = [owner];
    const candidates = random.sample(
      registered.filter((agent) => !protectedFree.has(agent.id) && agent.id !== owner.id && agent.teamIds.length < 2),
      registered.length,
    ).sort((left, right) => Number(right.provinceCode === province.code) - Number(left.provinceCode === province.code));
    for (const candidate of candidates) {
      if (roster.length >= rosterTarget) break;
      if (candidate.teamIds.length > 0 && candidate.persona !== "multi_team" && !random.bool(0.07)) continue;
      candidate.teamIds.push(teamId);
      roster.push(candidate);
    }
    const style = random.weighted([
      { value: "stable" as const, weight: 27 }, { value: "balanced" as const, weight: 24 },
      { value: "closed_friends" as const, weight: 16 }, { value: "high_rotation" as const, weight: 14 },
      { value: "veteran" as const, weight: 12 }, { value: "young" as const, weight: 7 },
    ]);
    teams.push({
      activity: random.weighted([
        { value: "high" as const, weight: 19 }, { value: "regular" as const, weight: 42 },
        { value: "casual" as const, weight: 23 }, { value: "low" as const, weight: 12 },
        { value: "abandoned" as const, weight: 4 },
      ]),
      adminAgentIds: [owner.id, ...random.sample(roster.slice(1), random.bool(0.38) ? 1 : 0).map(({ id }) => id)],
      challengePolicy: random.weighted([
        { value: "public" as const, weight: 52 }, { value: "private" as const, weight: 18 },
        { value: "invite_only" as const, weight: 22 }, { value: "temporarily_unavailable" as const, weight: 8 },
      ]),
      city: province.city,
      id: teamId,
      integrityClusterId: `independent:${teamId}`,
      marketPolicy: random.weighted([
        { value: "active" as const, weight: 46 }, { value: "seasonal" as const, weight: 34 },
        { value: "never" as const, weight: 20 },
      ]),
      modality,
      name: teamName(index),
      ownerAgentId: owner.id,
      playerIds: roster.map(({ id }) => id),
      productGroupId: null,
      provinceCode: province.code,
      strength: Math.round(roster.reduce((sum, agent) => sum + agent.ratingV2, 0) / roster.length * 10) / 10,
      style,
    });
  }

  // A legitimate club shares an owner and one player, but keeps independent squads.
  teams[1]!.ownerAgentId = teams[0]!.ownerAgentId;
  teams[1]!.adminAgentIds = [teams[0]!.ownerAgentId];
  teams[1]!.playerIds[0] = teams[0]!.playerIds[0]!;

  // Ten technical teams controlled by one operator share 90% of a core roster.
  const ring = teams.slice(-10);
  const ringOwner = ring[0]!.ownerAgentId;
  const shared = ring[0]!.playerIds.slice(0, 9);
  ring.forEach((team) => {
    team.ownerAgentId = ringOwner;
    team.adminAgentIds = [ringOwner];
    team.integrityClusterId = "synthetic-fake-team-ring";
    const uniquePlayer = [...team.playerIds].reverse().find((id) => !shared.includes(id));
    team.playerIds = uniquePlayer ? [...shared, uniquePlayer] : [...shared];
    team.challengePolicy = "public";
  });
  for (const agent of agents) {
    agent.teamIds = teams.filter((team) => team.playerIds.includes(agent.id)).map(({ id }) => id);
  }
  const displaced = registered.filter((agent) => !protectedFree.has(agent.id) && agent.teamIds.length === 0);
  for (const agent of displaced) {
    const candidates = teams
      .filter((team) => team.integrityClusterId !== "synthetic-fake-team-ring" && team.playerIds.length < 24)
      .sort((left, right) => (
        Number(right.provinceCode === agent.provinceCode) - Number(left.provinceCode === agent.provinceCode)
          || left.playerIds.length - right.playerIds.length
          || left.id.localeCompare(right.id)
      ));
    const team = candidates[0];
    if (!team) continue;
    team.playerIds.push(agent.id);
    agent.teamIds.push(team.id);
  }
  for (const team of teams) {
    const roster = team.playerIds.map((id) => agents.find((agent) => agent.id === id)).filter((agent): agent is SyntheticAgent => Boolean(agent));
    team.strength = Math.round(roster.reduce((sum, agent) => sum + agent.ratingV2, 0) / Math.max(1, roster.length) * 10) / 10;
  }
  return teams;
}

function createVenues(seed: number) {
  const random = new SeededRandom(`${seed}:venues`);
  return SYNTHETIC_PROVINCES.flatMap((province, provinceIndex) =>
    (["sala", "futbol7", "futbol11"] as const).map((modality, modalityIndex): SyntheticVenue => ({
      ...province,
      id: `venue-${province.code}-${modality}`,
      lat: province.lat + random.decimal(-0.035, 0.035),
      lng: province.lng + random.decimal(-0.035, 0.035),
      modality,
      name: `SIM · Municipal ${province.city} ${modalityIndex + 1}`,
      placeId: `synthetic-place-${provinceIndex + 1}-${modality}`,
    })),
  );
}

function initialCoverage(): SyntheticCoverage[] {
  return CANONICAL_CONTRACTS.map((contract) => ({
    failures: 0,
    flow: contract.flow,
    lastExecution: null,
    passes: 0,
    scenario: "canonical-contract",
    status: "NO_COVERAGE",
    timesExecuted: 0,
  }));
}

function gap(seed: number, index: number, category: SyntheticIncident["category"], operation: string, expected: string, actual: string): SyntheticIncident {
  return {
    actual: { behavior: actual }, actorAgentId: null, afterState: {}, beforeState: {}, category,
    expected: { behavior: expected }, id: deterministicUuid(`${seed}:gap`, index), occurrenceCount: 1,
    operation, relatedEntityIds: [], reproductionSteps: ["Open product inventory", `Inspect ${operation}`, "Compare canonical product contract"],
    severity: "info", status: category === "NEEDS_PRODUCT_DECISION" ? "needs_product_decision" : "open",
    virtualDate: DEFAULT_WORLD_START,
  };
}

export function createSyntheticWorld(options: {
  config?: Partial<SyntheticWorldConfig>;
  mode?: SyntheticWorldMode;
  name?: string;
  seed?: number;
} = {}): SyntheticWorld {
  const seed = options.seed ?? 20260809;
  const config = { ...DEFAULT_WORLD_CONFIG, ...options.config };
  const agents = createAgents(seed, config);
  const teams = createTeams(seed, agents, config);
  const venues = createVenues(seed);
  const id = deterministicUuid("pachangas-synthetic-world", `${seed}:${options.mode ?? "persistent"}:2026-27`);
  return {
    config,
    createdAt: new Date().toISOString(),
    currentDate: DEFAULT_WORLD_START,
    id,
    mode: options.mode ?? "persistent",
    name: options.name ?? `Pachangas IQ Synthetic World ${seed}`,
    revision: 0,
    seasonId: "2026-27",
    seed,
    sourceCommit: SYNTHETIC_SOURCE_COMMIT,
    startDate: DEFAULT_WORLD_START,
    state: {
      achievements: [],
      agents,
      attendanceRecords: [],
      boxes: [],
      challenges: [],
      coverage: initialCoverage(),
      conductScenarios: [],
      eventSequence: 0,
      events: [],
      incidents: [
        ...knownIncidentsForWorld(seed, DEFAULT_WORLD_START),
        gap(seed, 20, "TESTABILITY_GAP", "virtual-clock.product-sql", "RPC time injection", "352 SQL time dependencies use server clock"),
      ],
      matches: [],
      notifications: [],
      ratingOpinions: [],
      rankings: [],
      teams,
      venues,
    },
    status: "paused",
  };
}
