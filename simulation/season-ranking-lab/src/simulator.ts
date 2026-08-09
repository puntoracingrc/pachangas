import { DeterministicRandom, clamp, round } from "./random";
import { AUTONOMOUS_COMMUNITIES, TERRITORIES, TERRITORY_BY_PROVINCE } from "./territories";
import type {
  MatchKind,
  MatchStatus,
  PlayerMatchEvidence,
  Position,
  Season,
  SeasonPlayerInput,
  SyntheticPlayer,
  SyntheticTeam,
} from "./types";

export type SimulationWorld = {
  inputsBySeason: Map<string, SeasonPlayerInput[]>;
  players: SyntheticPlayer[];
  seasons: Season[];
  teams: SyntheticTeam[];
};

const positions: Position[] = ["POR", "DEF", "DEF", "MC", "MC", "DEL", "DEF", "MC", "DEL", "DEF"];

function isoDate(startYear: number, week: number, dayOffset: number) {
  const date = new Date(Date.UTC(startYear, 7, 1 + week * 7 + dayOffset, 18 + (week % 4), 0, 0));
  return date.toISOString();
}

function weightedTerritory(random: DeterministicRandom) {
  const weights = TERRITORIES.map(({ density }) => density === "dense" ? 6 : density === "medium" ? 2.5 : 1);
  return random.weightedPick(TERRITORIES, weights);
}

function statusFor(random: DeterministicRandom): MatchStatus {
  const roll = random.next();
  if (roll < 0.9) return "confirmed";
  if (roll < 0.96) return "auto_confirmed";
  if (roll < 0.975) return "disputed";
  if (roll < 0.988) return "draft";
  return "cancelled";
}

function kindFor(random: DeterministicRandom): MatchKind {
  return random.bool(0.055) ? "internal" : "challenge";
}

function sampleRoster(random: DeterministicRandom, playerIds: string[]) {
  const roster = playerIds.filter(() => random.bool(0.78));
  if (roster.length >= Math.min(6, playerIds.length)) return roster;
  return playerIds.slice(0, Math.min(7, playerIds.length));
}

function teamResult(random: DeterministicRandom, homeRating: number, awayRating: number): [0 | 0.5 | 1, 0 | 0.5 | 1] {
  const expectedHome = 1 / (1 + 10 ** ((awayRating - homeRating) / 32));
  const drawProbability = 0.12 + (1 - Math.abs(expectedHome - 0.5) * 2) * 0.13;
  const roll = random.next();
  if (roll < drawProbability) return [0.5, 0.5];
  return random.next() < expectedHome ? [1, 0] : [0, 1];
}

function goalAllocation(
  random: DeterministicRandom,
  participants: string[],
  playersById: Map<string, SyntheticPlayer>,
  result: 0 | 0.5 | 1,
) {
  const teamGoals = result === 1 ? random.integer(1, 5) : result === 0.5 ? random.integer(0, 3) : random.integer(0, 2);
  const goals = new Map<string, number>();
  const positionWeights: Record<Position, number> = { DEF: 1, DEL: 4, MC: 2.2, POR: 0.08 };
  const weights = participants.map((id) => positionWeights[playersById.get(id)?.position ?? "MC"]);
  for (let index = 0; index < teamGoals; index += 1) {
    const scorer = random.weightedPick(participants, weights);
    goals.set(scorer, (goals.get(scorer) ?? 0) + 1);
  }
  return goals;
}

function createSeasons(count: number): Season[] {
  return Array.from({ length: count }, (_, index) => {
    const startYear = 2026 + index;
    return {
      endsAt: `${startYear + 1}-07-31T23:59:59.999Z`,
      id: `season-${startYear}-${String(startYear + 1).slice(-2)}`,
      label: `${startYear}/${String(startYear + 1).slice(-2)}`,
      startsAt: `${startYear}-08-01T00:00:00.000Z`,
      status: index === count - 1 ? "active" : "closed",
    };
  });
}

function createTeams(random: DeterministicRandom, teamCount: number): SyntheticTeam[] {
  const clubClusters: string[] = [];
  return Array.from({ length: teamCount }, (_, index) => {
    const territory = weightedTerritory(random);
    const sharedClub = random.bool(0.08) && clubClusters.length > 0;
    const ownerClusterId = sharedClub ? random.pick(clubClusters) : `owner-${String(index + 1).padStart(4, "0")}`;
    if (!sharedClub) clubClusters.push(ownerClusterId);
    return {
      activityRate: clamp(random.normal(0.64, 0.22), 0.15, 1),
      id: `team-${String(index + 1).padStart(4, "0")}`,
      latentStrength: clamp(random.normal(72, 11), 35, 96),
      ownerClusterId,
      playerIds: [],
      provinceCode: territory.provinceCode,
    };
  });
}

function createPlayers(
  random: DeterministicRandom,
  playerCount: number,
  teams: SyntheticTeam[],
  teamSize: number,
) {
  return Array.from({ length: playerCount }, (_, index): SyntheticPlayer => {
    const primaryTeam = teams[Math.min(teams.length - 1, Math.floor(index / teamSize))]!;
    const reliability = clamp(random.normal(0.78, 0.15), 0.3, 1);
    const latentSkill = clamp(primaryTeam.latentStrength + random.normal(0, 8), 30, 98);
    const ratingV2 = clamp(latentSkill + random.normal(0, (1 - reliability) * 16 + 2.5), 25, 99);
    const joinedRoll = random.next();
    const player: SyntheticPlayer = {
      accountAgeDays: random.integer(30, 2200),
      id: `player-${String(index + 1).padStart(5, "0")}`,
      joinedSeasonIndex: joinedRoll < 0.82 ? 0 : joinedRoll < 0.93 ? 1 : 2,
      latentSkill: round(latentSkill),
      mobility: clamp(random.normal(0.12, 0.12), 0, 0.75),
      position: positions[index % positions.length]!,
      ratingReliability: round(reliability, 4),
      ratingV2: round(ratingV2),
      teamIds: [primaryTeam.id],
    };
    primaryTeam.playerIds.push(player.id);
    return player;
  });
}

function candidateOpponents(team: SyntheticTeam, teams: SyntheticTeam[], random: DeterministicRandom) {
  const territory = TERRITORY_BY_PROVINCE.get(team.provinceCode);
  const roll = random.next();
  let candidates: SyntheticTeam[];
  if (roll < 0.68) {
    candidates = teams.filter((candidate) => candidate.id !== team.id && candidate.provinceCode === team.provinceCode);
  } else if (roll < 0.9 && territory?.autonomousCommunityCode) {
    const provinces = new Set(AUTONOMOUS_COMMUNITIES.find(({ code }) => code === territory.autonomousCommunityCode)?.provinceCodes ?? []);
    candidates = teams.filter((candidate) => candidate.id !== team.id && provinces.has(candidate.provinceCode));
  } else {
    candidates = teams.filter((candidate) => candidate.id !== team.id);
  }
  return candidates.length > 0 ? candidates : teams.filter((candidate) => candidate.id !== team.id);
}

function selectVenueProvince(home: SyntheticTeam, away: SyntheticTeam, random: DeterministicRandom) {
  if (random.bool(0.74)) return home.provinceCode;
  if (random.bool(0.7)) return away.provinceCode;
  const homeCommunity = TERRITORY_BY_PROVINCE.get(home.provinceCode)?.autonomousCommunityCode;
  const nearby = TERRITORIES.filter(({ autonomousCommunityCode }) => autonomousCommunityCode === homeCommunity);
  return (nearby.length > 0 ? random.pick(nearby) : weightedTerritory(random)).provinceCode;
}

function addEvidence(
  recordsByPlayer: Map<string, PlayerMatchEvidence[]>,
  playerIds: string[],
  goals: Map<string, number>,
  evidence: Omit<PlayerMatchEvidence, "goals">,
) {
  for (const playerId of playerIds) {
    const records = recordsByPlayer.get(playerId) ?? [];
    records.push({ ...evidence, goals: goals.get(playerId) ?? 0 });
    recordsByPlayer.set(playerId, records);
  }
}

function createSeasonInputs(
  random: DeterministicRandom,
  season: Season,
  seasonIndex: number,
  players: SyntheticPlayer[],
  teams: SyntheticTeam[],
) {
  const playersById = new Map(players.map((player) => [player.id, player]));
  const activePlayers = new Set(players.filter(({ joinedSeasonIndex }) => joinedSeasonIndex <= seasonIndex).map(({ id }) => id));
  const activeTeams = teams.filter((team) => team.playerIds.some((id) => activePlayers.has(id)));
  const recordsByPlayer = new Map<string, PlayerMatchEvidence[]>();
  const matchCounts = new Map<string, number>();
  const recurringOpponents = new Map<string, string[]>();
  const usedPairWeeks = new Set<string>();
  let challengeSequence = 0;

  const teamRatings = new Map(activeTeams.map((team) => {
    const roster = team.playerIds.map((id) => playersById.get(id)).filter((player): player is SyntheticPlayer => Boolean(player));
    return [team.id, roster.reduce((sum, player) => sum + player.ratingV2, 0) / Math.max(1, roster.length)] as const;
  }));

  for (const home of activeTeams) {
    const target = Math.round(7 + home.activityRate * 31);
    let attempts = 0;
    while ((matchCounts.get(home.id) ?? 0) < target && attempts < target * 9) {
      attempts += 1;
      const recurring = recurringOpponents.get(home.id) ?? [];
      const away = recurring.length > 0 && random.bool(0.32)
        ? activeTeams.find(({ id }) => id === random.pick(recurring))
        : random.pick(candidateOpponents(home, activeTeams, random));
      if (!away || away.id === home.id) continue;
      const week = random.integer(1, 48);
      const pair = [home.id, away.id].sort().join(":");
      const pairWeek = `${pair}:${week}`;
      if (usedPairWeeks.has(pairWeek)) continue;
      usedPairWeeks.add(pairWeek);
      recurringOpponents.set(home.id, [...new Set([...recurring, away.id])]);
      recurringOpponents.set(away.id, [...new Set([...(recurringOpponents.get(away.id) ?? []), home.id])]);
      matchCounts.set(home.id, (matchCounts.get(home.id) ?? 0) + 1);
      matchCounts.set(away.id, (matchCounts.get(away.id) ?? 0) + 1);

      const homeRoster = sampleRoster(random, home.playerIds.filter((id) => activePlayers.has(id)));
      const awayRoster = sampleRoster(random, away.playerIds.filter((id) => activePlayers.has(id)));
      if (homeRoster.length === 0 || awayRoster.length === 0) continue;
      const homeRating = teamRatings.get(home.id) ?? home.latentStrength;
      const awayRating = teamRatings.get(away.id) ?? away.latentStrength;
      const [homeResult, awayResult] = teamResult(random, homeRating, awayRating);
      const goalMargin = homeResult === 0.5 ? 0 : random.integer(1, 5);
      const status = statusFor(random);
      const kind = kindFor(random);
      const occurredAt = isoDate(2026 + seasonIndex, week, random.integer(0, 5));
      const provinceCode = selectVenueProvince(home, away, random);
      const challengeId = `${season.id}-challenge-${String(++challengeSequence).padStart(6, "0")}`;
      const sharedOwner = home.ownerClusterId === away.ownerClusterId;
      const independence = sharedOwner ? 0.72 : 1;

      addEvidence(recordsByPlayer, homeRoster, goalAllocation(random, homeRoster, playersById, homeResult), {
        challengeId,
        kind,
        occurredAt,
        opponentClusterId: away.ownerClusterId,
        opponentIndependence: independence,
        opponentRating: awayRating,
        opponentTeamId: away.id,
        participated: true,
        participationConfidence: 1,
        provinceCode,
        result: homeResult,
        status,
        teamGoalDifference: homeResult === 1 ? goalMargin : homeResult === 0 ? -goalMargin : 0,
        teamRating: homeRating,
        venueConfidence: 0.98,
        week,
      });
      addEvidence(recordsByPlayer, awayRoster, goalAllocation(random, awayRoster, playersById, awayResult), {
        challengeId,
        kind,
        occurredAt,
        opponentClusterId: home.ownerClusterId,
        opponentIndependence: independence,
        opponentRating: homeRating,
        opponentTeamId: home.id,
        participated: true,
        participationConfidence: 1,
        provinceCode,
        result: awayResult,
        status,
        teamGoalDifference: awayResult === 1 ? goalMargin : awayResult === 0 ? -goalMargin : 0,
        teamRating: awayRating,
        venueConfidence: 0.98,
        week,
      });
    }
  }

  return players.map((player): SeasonPlayerInput => ({
    player,
    previousCompetitiveProvinceCode: null,
    records: recordsByPlayer.get(player.id) ?? [],
    seasonId: season.id,
  }));
}

export function createSimulationWorld(options: {
  playerCount?: number;
  seasonCount?: number;
  seed?: number;
  teamSize?: number;
} = {}): SimulationWorld {
  const playerCount = options.playerCount ?? 10_000;
  const seasonCount = options.seasonCount ?? 3;
  const teamSize = options.teamSize ?? 10;
  const random = new DeterministicRandom(options.seed ?? 20_260_809);
  const seasons = createSeasons(seasonCount);
  const teams = createTeams(random, Math.ceil(playerCount / teamSize));
  const players = createPlayers(random, playerCount, teams, teamSize);
  const inputsBySeason = new Map(seasons.map((season, index) => [
    season.id,
    createSeasonInputs(random, season, index, players, teams),
  ]));
  return { inputsBySeason, players, seasons, teams };
}
