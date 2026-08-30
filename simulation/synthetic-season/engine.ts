import { createHash } from "node:crypto";
import {
  generateLeagueRoundRobin,
  validateLeagueRoundRobin,
} from "../../app/league-round-robin-engine";
import { leagueSchedulingEngineVersion } from "../../app/league-scheduling-contract";
import {
  SYNTHETIC_SEASON_ENGINE_VERSION,
  SYNTHETIC_SEASON_SEED,
  SYNTHETIC_SEASON_VERSION,
  type SyntheticSeasonBracketNode,
  type SyntheticSeasonCheckpoint,
  type SyntheticSeasonCheckpointHashes,
  type SyntheticSeasonCheckpointId,
  type SyntheticSeasonClub,
  type SyntheticSeasonCompetition,
  type SyntheticSeasonDisciplineEvent,
  type SyntheticSeasonFaultOutcome,
  type SyntheticSeasonIndex,
  type SyntheticSeasonMatch,
  type SyntheticSeasonMatchSheet,
  type SyntheticSeasonMatchResult,
  type SyntheticSeasonNotification,
  type SyntheticSeasonPlayer,
  type SyntheticSeasonProof,
  type SyntheticSeasonReferee,
  type SyntheticSeasonSanction,
  type SyntheticSeasonStandingRow,
  type SyntheticSeasonTeam,
} from "../../app/demo-world/demo-world-v3-2-contract";
import authorityProof from "../../scripts/demo-world/demo-world-v2-authority-proof.json";
import teamOperationalProof from "../../scripts/demo-world/team-operational-v31-authority-proof.json";

export const SYNTHETIC_SEASON_GENERATED_AT = "2026-08-30T14:00:00.000Z";
export const SYNTHETIC_SEASON_DEMO_NOW = "2027-01-10T20:00:00.000Z";

type SyntheticSeasonBuild = {
  checkpoints: SyntheticSeasonCheckpoint[];
  disciplineEvents: SyntheticSeasonDisciplineEvent[];
  index: SyntheticSeasonIndex;
  notifications: SyntheticSeasonNotification[];
  sanctions: SyntheticSeasonSanction[];
};

const checkpointDefinitions: Array<{ checkpoint: SyntheticSeasonCheckpointId; label: string; week: number }> = [
  { checkpoint: 0, label: "Pretemporada", week: 0 },
  { checkpoint: 1, label: "Inscripciones", week: 1 },
  { checkpoint: 2, label: "Planificación", week: 3 },
  { checkpoint: 3, label: "Inicio", week: 4 },
  { checkpoint: 4, label: "Mitad", week: 8 },
  { checkpoint: 5, label: "Recta final", week: 12 },
  { checkpoint: 6, label: "Clasificación", week: 13 },
  { checkpoint: 7, label: "Finales", week: 15 },
  { checkpoint: 8, label: "Postemporada", week: 16 },
];

const teamNames = [
  "Cobalto Raval", "Circuit Poblenou", "Brúixola Sants", "Onze del Clot",
  "Marina Fosca", "Ferro Sant Andreu", "Diagonal 26", "Vértice Gràcia",
  "Pols Sabadell", "Carboni Terrassa", "Metro Rubí", "Nexe Granollers",
  "Línia Cerdanyola", "Vector Sant Cugat", "Ronda Mollet", "Taller Barberà",
  "Riu Girona", "Marge Salt", "Estany Banyoles", "Tramuntana 9",
  "Costa Blanes", "Volcà Olot", "Marea Mataró", "Fòrum Badalona",
  "Premià Set", "Nord Masnou", "Blau Vilassar", "Riera Arenys",
  "Delta Castelldefels", "Bosc Cardedeu", "Far Montcada", "Pont Vic",
] as const;

const locations = [
  "Barcelona", "Barcelona", "Barcelona", "Barcelona", "Barcelona", "Barcelona", "Barcelona", "Barcelona",
  "Sabadell", "Terrassa", "Rubí", "Granollers", "Cerdanyola", "Sant Cugat", "Mollet", "Barberà",
  "Girona", "Salt", "Banyoles", "Figueres", "Blanes", "Olot", "Mataró", "Badalona",
  "Premià", "El Masnou", "Vilassar", "Arenys", "Castelldefels", "Cardedeu", "Montcada", "Vic",
] as const;

const positions: SyntheticSeasonPlayer["position"][] = [
  "POR", "DFC", "LD", "LI", "PIV", "MC", "MCO", "ED", "EI", "DC", "DFC", "MC", "DC", "PIV", "POR",
];

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .filter(([key]) => !["capturedAt", "generatedAt"].includes(key))
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => [key, stableValue(item)]));
  }
  return value;
}

export function syntheticSeasonHash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(stableValue(value))).digest("hex");
}

function shortId(prefix: string, index: number) {
  return `${prefix}_${String(index).padStart(3, "0")}`;
}

function hashNumber(value: string) {
  return Number.parseInt(syntheticSeasonHash(value).slice(0, 8), 16);
}

function weekDate(week: number, slot: number) {
  const date = new Date("2026-09-07T18:00:00.000Z");
  const normalizedSlot = slot % 28;
  const time = normalizedSlot % 4;
  date.setUTCDate(date.getUTCDate() + week * 7 + Math.floor(normalizedSlot / 4));
  date.setUTCHours(18 + time, time % 2 ? 30 : 0, 0, 0);
  return date.toISOString();
}

function assignNonOverlappingKickoffs(matches: readonly SyntheticSeasonMatch[]) {
  const occupied = new Set<string>();
  return [...matches]
    .sort((left, right) => left.week - right.week || left.canonicalMatchId.localeCompare(right.canonicalMatchId))
    .map((match) => {
      const preferredSlot = hashNumber(`${SYNTHETIC_SEASON_SEED}:kickoff:${match.canonicalMatchId}`) % 28;
      for (let offset = 0; offset < 28; offset += 1) {
        const scheduledAt = weekDate(match.week, preferredSlot + offset);
        const homeKey = `${match.homeTeamId}|${scheduledAt}`;
        const awayKey = `${match.awayTeamId}|${scheduledAt}`;
        if (occupied.has(homeKey) || occupied.has(awayKey)) continue;
        occupied.add(homeKey);
        occupied.add(awayKey);
        return { ...match, scheduledAt };
      }
      throw new Error(`SYNTHETIC_TEAM_CALENDAR_CAPACITY_EXHAUSTED:${match.canonicalMatchId}`);
    })
    .sort((left, right) => left.canonicalMatchId.localeCompare(right.canonicalMatchId));
}

function buildClubs(): SyntheticSeasonClub[] {
  const definitions: Array<Omit<SyntheticSeasonClub, "id" | "teamIds">> = [
    { name: "Club Barrios IQ", organizerAccess: "PARTNER", publicInDemo: true, status: "ACTIVE", story: "Partner aprobado y organizador de la Liga Barrios IQ." },
    { name: "Club Copa Oberta", organizerAccess: "PRIVATE_BETA", publicInDemo: true, status: "ACTIVE", story: "Private beta que organiza la Copa Barrios IQ." },
    { name: "Club Nit Esportiva", organizerAccess: "PRIVATE_BETA", publicInDemo: false, status: "ACTIVE", story: "Organiza la Liga Nocturna privada." },
    { name: "Club Interès Pro", organizerAccess: "APPROVED_INTEREST", publicInDemo: false, status: "ACTIVE", story: "Interés de plan registrado, sin grant de suscripción." },
    { name: "Club Xarxa Arbitral", organizerAccess: "PARTNER", publicInDemo: true, status: "ACTIVE", story: "Relaciona varios equipos y una red arbitral ficticia." },
    { name: "Club Memòria", organizerAccess: "PRIVATE_BETA", publicInDemo: false, status: "ARCHIVED", story: "Archivado al terminar la temporada, con historia deportiva preservada." },
  ];
  return definitions.map((definition, index) => ({
    ...definition,
    id: shortId("synthetic_club", index + 1),
    teamIds: teamNames.map((_, teamIndex) => shortId("synthetic_team", teamIndex + 1))
      .filter((_, teamIndex) => teamIndex % definitions.length === index),
  }));
}

function finalTeamState(index: number): Pick<SyntheticSeasonTeam, "billingState" | "ownerTransferred" | "restrictionPreset" | "state"> {
  if (index === 24) return { billingState: "ACTIVE", ownerTransferred: false, restrictionPreset: "CLEAR", state: "UNDER_REVIEW" };
  if (index === 25) return { billingState: "ACTIVE", ownerTransferred: false, restrictionPreset: "SOCIAL_ONLY", state: "LIMITED" };
  if (index === 26) return { billingState: "ACTIVE", ownerTransferred: false, restrictionPreset: "NEW_ACTIVITY_ONLY", state: "SUSPENDED" };
  if (index === 27) return { billingState: "ACTIVE", ownerTransferred: false, restrictionPreset: "CLEAR", state: "ARCHIVED" };
  if (index === 28) return { billingState: "ACTIVE", ownerTransferred: true, restrictionPreset: "CLEAR", state: "ACTIVE" };
  if (index === 29) return { billingState: "INACTIVE", ownerTransferred: false, restrictionPreset: "CLEAR", state: "ACTIVE" };
  return { billingState: "ACTIVE", ownerTransferred: false, restrictionPreset: "CLEAR", state: "ACTIVE" };
}

function buildTeams(clubs: SyntheticSeasonClub[]): SyntheticSeasonTeam[] {
  return teamNames.map((name, index) => {
    const finalState = finalTeamState(index);
    const blockedSocial = finalState.state === "LIMITED" && finalState.restrictionPreset === "SOCIAL_ONLY";
    const archived = finalState.state === "ARCHIVED";
    return {
      ...finalState,
      challengesAllowed: !blockedSocial && !archived,
      clubId: clubs[index % clubs.length]!.id,
      competitionContinuity: true,
      id: shortId("synthetic_team", index + 1),
      marketplaceAllowed: !blockedSocial && !archived,
      name,
      publicLocation: locations[index]!,
    };
  });
}

function buildPlayers(teams: SyntheticSeasonTeam[]): SyntheticSeasonPlayer[] {
  return teams.flatMap((team, teamIndex) => positions.map((position, rosterIndex) => {
    const index = teamIndex * positions.length + rosterIndex + 1;
    const profile: SyntheticSeasonPlayer["profile"] = rosterIndex === 0
      ? "REGULAR"
      : rosterIndex >= 12
        ? "SUBSTITUTE"
        : index % 17 === 0
          ? "GUEST"
          : index % 13 === 0
            ? "IRREGULAR"
            : [7, 9].includes(rosterIndex)
              ? "SCORER"
              : "REGULAR";
    return {
      id: shortId("synthetic_player", index),
      name: `Jugador Demo ${String(index).padStart(3, "0")}`,
      position,
      profile,
      sanctioned: index % 79 === 0,
      teamId: team.id,
    };
  }));
}

function buildReferees(clubs: SyntheticSeasonClub[]): SyntheticSeasonReferee[] {
  return Array.from({ length: 12 }, (_, index) => ({
    assignmentCount: 0,
    clubIds: index < 6 ? [clubs[index % clubs.length]!.id] : [clubs[4]!.id],
    id: shortId("synthetic_referee", index + 1),
    modalities: index % 3 === 0 ? ["FOOTBALL_7", "FUTSAL"] : index % 2 === 0 ? ["FUTSAL"] : ["FOOTBALL_7"],
    name: `Árbitro Demo ${String(index + 1).padStart(2, "0")}`,
    publicFeeConsent: index % 4 === 0,
    zone: ["Barcelona", "Vallès", "Girona", "Maresme"][index % 4]!,
  }));
}

function buildCompetitions(clubs: SyntheticSeasonClub[], teams: SyntheticSeasonTeam[]): SyntheticSeasonCompetition[] {
  const teamIds = teams.map(({ id }) => id);
  return [
    {
      clubId: clubs[0]!.id,
      id: "synthetic_league_a",
      kind: "LEAGUE",
      modality: "FOOTBALL_7",
      name: "Liga Barrios IQ",
      publicInDemo: true,
      refereePolicy: "REQUIRED",
      ruleRevision: "rule_revision_league_a_v1",
      status: "COMPLETED",
      teamIds: teamIds.slice(0, 10),
      visibility: "PUBLIC",
    },
    {
      clubId: clubs[2]!.id,
      id: "synthetic_league_b",
      kind: "LEAGUE",
      modality: "FUTSAL",
      name: "Liga Nocturna IQ",
      publicInDemo: false,
      refereePolicy: "OPTIONAL",
      ruleRevision: "rule_revision_league_b_v1",
      status: "COMPLETED",
      teamIds: teamIds.slice(10, 18),
      visibility: "PRIVATE",
    },
    {
      clubId: clubs[1]!.id,
      id: "synthetic_tournament_a",
      kind: "TOURNAMENT",
      modality: "FOOTBALL_7",
      name: "Copa Barrios IQ",
      publicInDemo: true,
      refereePolicy: "REQUIRED",
      ruleRevision: "rule_revision_tournament_a_v1",
      status: "COMPLETED",
      teamIds: teamIds.slice(0, 16),
      visibility: "PUBLIC",
    },
    {
      clubId: clubs[4]!.id,
      id: "synthetic_tournament_b",
      kind: "TOURNAMENT",
      modality: "FUTSAL",
      name: "Copa Relámpago IQ",
      publicInDemo: false,
      refereePolicy: "OPTIONAL",
      ruleRevision: "rule_revision_tournament_b_v1",
      status: "COMPLETED",
      teamIds: teamIds.slice(24, 32),
      visibility: "UNLISTED",
    },
  ];
}

function anomalyFor(index: number): SyntheticSeasonMatch["anomaly"] {
  if ([29, 77, 117].includes(index)) return "NO_SHOW";
  if ([43, 91, 122].includes(index)) return "SUSPENDED";
  if ([37, 61, 83, 101, 125].includes(index)) return "DISPUTED";
  if ([13, 27, 52, 66, 79, 102, 116].includes(index)) return "POSTPONED";
  if ([18, 72, 108].includes(index)) return "VENUE_CHANGED";
  return "NORMAL";
}

function resultFor(id: string, homeTeamId: string, awayTeamId: string, knockout = false, anomaly: SyntheticSeasonMatch["anomaly"] = "NORMAL"): SyntheticSeasonMatchResult {
  if (anomaly === "NO_SHOW") {
    return { away: 0, decidedBy: "FORFEIT", home: 3, penaltiesAway: null, penaltiesHome: null, winnerTeamId: homeTeamId };
  }
  const seed = hashNumber(`${SYNTHETIC_SEASON_SEED}:${id}`);
  const home = seed % 5;
  let away = Math.floor(seed / 7) % 5;
  if (!knockout) {
    return {
      away,
      decidedBy: "NORMAL",
      home,
      penaltiesAway: null,
      penaltiesHome: null,
      winnerTeamId: home === away ? null : home > away ? homeTeamId : awayTeamId,
    };
  }
  if (home === away) {
    if (seed % 2 === 0) {
      return {
        away,
        decidedBy: "PENALTIES",
        home,
        penaltiesAway: 3,
        penaltiesHome: 4,
        winnerTeamId: homeTeamId,
      };
    }
    away += 1;
    return { away, decidedBy: "EXTRA_TIME", home, penaltiesAway: null, penaltiesHome: null, winnerTeamId: awayTeamId };
  }
  return {
    away,
    decidedBy: seed % 11 === 0 ? "EXTRA_TIME" : "NORMAL",
    home,
    penaltiesAway: null,
    penaltiesHome: null,
    winnerTeamId: home > away ? homeTeamId : awayTeamId,
  };
}

function matchRecord(input: Omit<SyntheticSeasonMatch, "anomaly" | "canonicalMatchId" | "refereeAssignmentId" | "refereeId" | "result" | "scheduledAt" | "venue"> & { index: number; knockout?: boolean }): SyntheticSeasonMatch {
  const canonicalMatchId = shortId("synthetic_match", input.index);
  const anomaly = anomalyFor(input.index);
  const optionalReferee = input.competitionId === "synthetic_league_b" || input.competitionId === "synthetic_tournament_b" || input.kind === "CHALLENGE";
  const hasReferee = !optionalReferee || input.index % 4 !== 0;
  const refereeNumber = input.index % 12 + 1;
  return {
    anomaly,
    awayTeamId: input.awayTeamId,
    canonicalMatchId,
    competitionId: input.competitionId,
    homeTeamId: input.homeTeamId,
    kind: input.kind,
    refereeAssignmentId: hasReferee ? shortId("synthetic_assignment", input.index) : null,
    refereeId: hasReferee ? shortId("synthetic_referee", refereeNumber) : null,
    result: resultFor(canonicalMatchId, input.homeTeamId, input.awayTeamId, input.knockout, anomaly),
    round: input.round,
    scheduledAt: weekDate(input.week, input.index),
    stage: input.stage,
    venue: anomaly === "VENUE_CHANGED" ? "Pista Demo Alternativa" : "Campo Demo Canónico",
    week: input.week,
  };
}

function assignNonOverlappingReferees(
  matches: readonly SyntheticSeasonMatch[],
  competitions: readonly SyntheticSeasonCompetition[],
  referees: readonly SyntheticSeasonReferee[],
) {
  const usedByKickoff = new Map<string, Set<string>>();
  const competitionModalities = new Map(competitions.map(({ id, modality }) => [id, modality]));
  const refereeProfiles = new Map(referees.map((referee) => [referee.id, referee]));
  return [...matches]
    .sort((left, right) => left.scheduledAt.localeCompare(right.scheduledAt)
      || left.canonicalMatchId.localeCompare(right.canonicalMatchId))
    .map((match) => {
      if (!match.refereeAssignmentId) return match;
      const used = usedByKickoff.get(match.scheduledAt) ?? new Set<string>();
      const preferredIndex = hashNumber(`${SYNTHETIC_SEASON_SEED}:referee:${match.canonicalMatchId}`) % 12;
      let refereeId: string | null = null;
      for (let offset = 0; offset < 12; offset += 1) {
        const candidate = shortId("synthetic_referee", (preferredIndex + offset) % 12 + 1);
        const modality = match.competitionId
          ? competitionModalities.get(match.competitionId)
          : "FOOTBALL_7";
        if (!modality) throw new Error(`SYNTHETIC_COMPETITION_MODALITY_MISSING:${match.competitionId}`);
        if (used.has(candidate) || !refereeProfiles.get(candidate)?.modalities.includes(modality)) continue;
        refereeId = candidate;
        break;
      }
      if (!refereeId) throw new Error(`SYNTHETIC_REFEREE_CAPACITY_EXHAUSTED:${match.scheduledAt}`);
      used.add(refereeId);
      usedByKickoff.set(match.scheduledAt, used);
      return { ...match, refereeId };
    })
    .sort((left, right) => left.canonicalMatchId.localeCompare(right.canonicalMatchId));
}

function refereeOverlapCount(matches: readonly SyntheticSeasonMatch[]) {
  const assignments = new Map<string, number>();
  for (const match of matches) {
    if (!match.refereeId) continue;
    const key = `${match.refereeId}|${match.scheduledAt}`;
    assignments.set(key, (assignments.get(key) ?? 0) + 1);
  }
  return [...assignments.values()].filter((count) => count > 1).length;
}

function teamOverlapCount(matches: readonly SyntheticSeasonMatch[]) {
  const appearances = new Map<string, number>();
  for (const match of matches) {
    for (const teamId of [match.homeTeamId, match.awayTeamId]) {
      const key = `${teamId}|${match.scheduledAt}`;
      appearances.set(key, (appearances.get(key) ?? 0) + 1);
    }
  }
  return [...appearances.values()].filter((count) => count > 1).length;
}

function refereeModalityMismatchCount(
  matches: readonly SyntheticSeasonMatch[],
  competitions: readonly SyntheticSeasonCompetition[],
  referees: readonly SyntheticSeasonReferee[],
) {
  const competitionModalities = new Map(competitions.map(({ id, modality }) => [id, modality]));
  const refereeProfiles = new Map(referees.map((referee) => [referee.id, referee]));
  return matches.filter((match) => {
    if (!match.refereeId) return false;
    const modality = match.competitionId
      ? competitionModalities.get(match.competitionId)
      : "FOOTBALL_7";
    return !modality || !refereeProfiles.get(match.refereeId)?.modalities.includes(modality);
  }).length;
}

function leagueMatches(competition: SyntheticSeasonCompetition, startIndex: number, weekStart: number) {
  const schedule = generateLeagueRoundRobin(competition.teamIds, {
    legs: 1,
    seed: `${SYNTHETIC_SEASON_SEED}:${competition.id}`,
  });
  const validation = validateLeagueRoundRobin(schedule);
  if (validation.fixtureCount !== validation.expectedFixtures || validation.duplicatePairings !== 0) {
    throw new Error(`PRODUCTION_SCHEDULE_INVALID:${competition.id}`);
  }
  return schedule.rounds.flatMap((round) => round.fixtures.map((fixture, fixtureIndex) => matchRecord({
    awayTeamId: fixture.awayEntryId,
    competitionId: competition.id,
    homeTeamId: fixture.homeEntryId,
    index: startIndex + (round.roundNumber - 1) * round.fixtures.length + fixtureIndex,
    kind: "LEAGUE",
    round: round.roundNumber,
    stage: "LEAGUE",
    week: weekStart + (round.roundNumber - 1) % 9,
  })));
}

function standingsFor(teamIds: readonly string[], matches: readonly SyntheticSeasonMatch[]): SyntheticSeasonStandingRow[] {
  const rows = new Map(teamIds.map((teamId) => [teamId, {
    draws: 0,
    goalDifference: 0,
    goalsAgainst: 0,
    goalsFor: 0,
    losses: 0,
    played: 0,
    points: 0,
    position: 0,
    teamId,
    wins: 0,
  }]));
  for (const match of matches) {
    const home = rows.get(match.homeTeamId);
    const away = rows.get(match.awayTeamId);
    if (!home || !away) continue;
    home.played += 1;
    away.played += 1;
    home.goalsFor += match.result.home;
    home.goalsAgainst += match.result.away;
    away.goalsFor += match.result.away;
    away.goalsAgainst += match.result.home;
    if (match.result.home === match.result.away) {
      home.draws += 1;
      away.draws += 1;
      home.points += 1;
      away.points += 1;
    } else if (match.result.home > match.result.away) {
      home.wins += 1;
      away.losses += 1;
      home.points += 3;
    } else {
      away.wins += 1;
      home.losses += 1;
      away.points += 3;
    }
  }
  return [...rows.values()]
    .map((row) => ({ ...row, goalDifference: row.goalsFor - row.goalsAgainst }))
    .sort((left, right) => right.points - left.points
      || right.goalDifference - left.goalDifference
      || right.goalsFor - left.goalsFor
      || left.teamId.localeCompare(right.teamId))
    .map((row, index) => ({ ...row, position: index + 1 }));
}

function groupStageMatches(competition: SyntheticSeasonCompetition, startIndex: number) {
  const groups = Array.from({ length: 4 }, (_, groupIndex) => competition.teamIds.filter((_, index) => index % 4 === groupIndex));
  const matches: SyntheticSeasonMatch[] = [];
  let index = startIndex;
  for (let groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
    const group = groups[groupIndex]!;
    const schedule = generateLeagueRoundRobin(group, {
      legs: 1,
      seed: `${SYNTHETIC_SEASON_SEED}:${competition.id}:group:${groupIndex + 1}`,
    });
    for (const round of schedule.rounds) for (const fixture of round.fixtures) {
      matches.push(matchRecord({
        awayTeamId: fixture.awayEntryId,
        competitionId: competition.id,
        homeTeamId: fixture.homeEntryId,
        index,
        kind: "TOURNAMENT_GROUP",
        round: round.roundNumber,
        stage: `GROUP_${String.fromCharCode(65 + groupIndex)}`,
        week: 5 + round.roundNumber,
      }));
      index += 1;
    }
  }
  return { groups, matches, nextIndex: index };
}

function knockoutMatch(index: number, competitionId: string, homeTeamId: string, awayTeamId: string, round: number, stage: SyntheticSeasonBracketNode["round"], week: number) {
  return matchRecord({ awayTeamId, competitionId, homeTeamId, index, kind: "TOURNAMENT_KNOCKOUT", knockout: true, round, stage, week });
}

function tournamentAKnockout(competition: SyntheticSeasonCompetition, groupMatches: SyntheticSeasonMatch[], startIndex: number) {
  const groups = Array.from({ length: 4 }, (_, groupIndex) => competition.teamIds.filter((_, index) => index % 4 === groupIndex));
  const qualified = groups.map((group, groupIndex) => standingsFor(group, groupMatches.filter(({ stage }) => stage === `GROUP_${String.fromCharCode(65 + groupIndex)}`)).slice(0, 2).map(({ teamId }) => teamId));
  const quarterPairs = [
    [qualified[0]![0]!, qualified[1]![1]!],
    [qualified[1]![0]!, qualified[0]![1]!],
    [qualified[2]![0]!, qualified[3]![1]!],
    [qualified[3]![0]!, qualified[2]![1]!],
  ];
  let index = startIndex;
  const matches: SyntheticSeasonMatch[] = quarterPairs.map(([home, away], pairIndex) => knockoutMatch(index++, competition.id, home, away, pairIndex + 1, "QUARTERFINAL", 12));
  const semifinalOne = knockoutMatch(index++, competition.id, matches[0]!.result.winnerTeamId!, matches[2]!.result.winnerTeamId!, 1, "SEMIFINAL", 14);
  const semifinalTwo = knockoutMatch(index++, competition.id, matches[1]!.result.winnerTeamId!, matches[3]!.result.winnerTeamId!, 2, "SEMIFINAL", 14);
  matches.push(semifinalOne, semifinalTwo);
  const loser = (match: SyntheticSeasonMatch) => match.result.winnerTeamId === match.homeTeamId ? match.awayTeamId : match.homeTeamId;
  const final = knockoutMatch(index++, competition.id, semifinalOne.result.winnerTeamId!, semifinalTwo.result.winnerTeamId!, 1, "FINAL", 15);
  const third = knockoutMatch(index++, competition.id, loser(semifinalOne), loser(semifinalTwo), 1, "THIRD_PLACE", 15);
  matches.push(final, third);
  return { matches, nextIndex: index, qualified: qualified.flat() };
}

function tournamentBKnockout(competition: SyntheticSeasonCompetition, startIndex: number) {
  let index = startIndex;
  const quarters: SyntheticSeasonMatch[] = Array.from({ length: 4 }, (_, pairIndex) => knockoutMatch(
    index++,
    competition.id,
    competition.teamIds[pairIndex]!,
    competition.teamIds[7 - pairIndex]!,
    pairIndex + 1,
    "QUARTERFINAL",
    7,
  ));
  const semis = [
    knockoutMatch(index++, competition.id, quarters[0]!.result.winnerTeamId!, quarters[1]!.result.winnerTeamId!, 1, "SEMIFINAL", 9),
    knockoutMatch(index++, competition.id, quarters[2]!.result.winnerTeamId!, quarters[3]!.result.winnerTeamId!, 2, "SEMIFINAL", 9),
  ];
  const final = knockoutMatch(index++, competition.id, semis[0]!.result.winnerTeamId!, semis[1]!.result.winnerTeamId!, 1, "FINAL", 10);
  return { matches: [...quarters, ...semis, final], nextIndex: index };
}

function buildMatches(
  competitions: SyntheticSeasonCompetition[],
  teams: SyntheticSeasonTeam[],
  referees: SyntheticSeasonReferee[],
) {
  const leagueA = leagueMatches(competitions[0]!, 1, 4);
  const leagueB = leagueMatches(competitions[1]!, 46, 4);
  const tournamentAGroup = groupStageMatches(competitions[2]!, 74);
  const tournamentAKo = tournamentAKnockout(competitions[2]!, tournamentAGroup.matches, tournamentAGroup.nextIndex);
  const tournamentB = tournamentBKnockout(competitions[3]!, tournamentAKo.nextIndex);
  let index = tournamentB.nextIndex;
  const challenges = Array.from({ length: 16 }, (_, challengeIndex) => {
    const home = teams[(challengeIndex * 3 + 2) % teams.length]!;
    const away = teams[(challengeIndex * 7 + 11) % teams.length]!;
    const safeAway = away.id === home.id ? teams[(challengeIndex * 7 + 12) % teams.length]! : away;
    return matchRecord({
      awayTeamId: safeAway.id,
      competitionId: null,
      homeTeamId: home.id,
      index: index++,
      kind: "CHALLENGE",
      round: challengeIndex + 1,
      stage: "CHALLENGE",
      week: 3 + challengeIndex % 12,
    });
  });
  const matches = assignNonOverlappingReferees(assignNonOverlappingKickoffs([
    ...leagueA,
    ...leagueB,
    ...tournamentAGroup.matches,
    ...tournamentAKo.matches,
    ...tournamentB.matches,
    ...challenges,
  ]), competitions, referees);
  if (matches.length !== 128) throw new Error(`SYNTHETIC_MATCH_COUNT_INVALID:${matches.length}`);
  return { challenges, matches, tournamentAQualified: tournamentAKo.qualified };
}

function bracketNodes(matches: readonly SyntheticSeasonMatch[]): SyntheticSeasonBracketNode[] {
  return matches.filter(({ kind }) => kind === "TOURNAMENT_KNOCKOUT").map((match) => ({
    awayTeamId: match.awayTeamId,
    homeTeamId: match.homeTeamId,
    id: `node_${match.canonicalMatchId}`,
    matchId: match.canonicalMatchId,
    round: match.stage as SyntheticSeasonBracketNode["round"],
    winnerTeamId: match.result.winnerTeamId!,
  }));
}

function hasOneChampionPerTournament(
  competitions: readonly SyntheticSeasonCompetition[],
  matches: readonly SyntheticSeasonMatch[],
) {
  return competitions
    .filter(({ kind, status }) => kind === "TOURNAMENT" && status === "COMPLETED")
    .every(({ id }) => {
      const finals = matches.filter(({ competitionId, stage }) => competitionId === id && stage === "FINAL");
      return finals.length === 1 && Boolean(finals[0]?.result.winnerTeamId);
    });
}

function buildDiscipline(matches: readonly SyntheticSeasonMatch[], players: readonly SyntheticSeasonPlayer[]) {
  const events: SyntheticSeasonDisciplineEvent[] = [];
  let eventIndex = 1;
  for (const [index, match] of matches.entries()) {
    if (index % 2 !== 0) continue;
    const teamPlayers = players.filter(({ teamId }) => teamId === (index % 4 === 0 ? match.homeTeamId : match.awayTeamId));
    const card: SyntheticSeasonDisciplineEvent["card"] = index === 56
      ? "BLUE"
      : index % 47 === 0
        ? "RED"
        : index % 31 === 0
          ? "SECOND_YELLOW"
          : "YELLOW";
    events.push({
      canonicalMatchId: match.canonicalMatchId,
      card,
      id: shortId("synthetic_discipline", eventIndex++),
      playerId: teamPlayers[index % teamPlayers.length]!.id,
      refereeAssignmentId: match.refereeAssignmentId,
      reportingRefereeId: match.refereeId,
      week: match.week,
    });
    if (index % 11 === 0) {
      events.push({
        canonicalMatchId: match.canonicalMatchId,
        card: "YELLOW",
        id: shortId("synthetic_discipline", eventIndex++),
        playerId: teamPlayers[(index + 3) % teamPlayers.length]!.id,
        refereeAssignmentId: match.refereeAssignmentId,
        reportingRefereeId: match.refereeId,
        week: match.week,
      });
    }
  }
  const sanctionedPlayers = [...new Set(events.filter(({ card }) => card !== "YELLOW").map(({ playerId }) => playerId))].slice(0, 9);
  const sanctions = sanctionedPlayers.map((playerId, index): SyntheticSeasonSanction => ({
    fulfilledAtWeek: Math.min(16, 7 + index),
    id: shortId("synthetic_sanction", index + 1),
    imposedAtWeek: 5 + index,
    playerId,
    status: "FULFILLED",
  }));
  return { events, sanctions };
}

function buildMatchSheets(
  matches: readonly SyntheticSeasonMatch[],
  players: readonly SyntheticSeasonPlayer[],
  sanctions: readonly SyntheticSeasonSanction[],
  competitions: readonly SyntheticSeasonCompetition[],
): SyntheticSeasonMatchSheet[] {
  const rosters = new Map<string, SyntheticSeasonPlayer[]>();
  for (const player of players) rosters.set(player.teamId, [...(rosters.get(player.teamId) ?? []), player]);
  const modalities = new Map(competitions.map(({ id, modality }) => [id, modality]));
  return matches.flatMap((match) => [match.homeTeamId, match.awayTeamId].map((teamId, sideIndex) => {
    const roster = [...(rosters.get(teamId) ?? [])].sort((left, right) => left.id.localeCompare(right.id));
    const activeSanctions = sanctions.filter(({ fulfilledAtWeek, imposedAtWeek, playerId }) => (
      roster.some(({ id }) => id === playerId)
      && imposedAtWeek < match.week
      && fulfilledAtWeek >= match.week
    ));
    const sanctionedPlayerIds = activeSanctions.map(({ playerId }) => playerId).sort();
    const available = roster.filter(({ id }) => !sanctionedPlayerIds.includes(id));
    const noShow = match.anomaly === "NO_SHOW" && sideIndex === 1;
    const modality = match.competitionId ? modalities.get(match.competitionId) : "FOOTBALL_7";
    if (!modality) throw new Error(`SYNTHETIC_MATCH_SHEET_MODALITY_MISSING:${match.canonicalMatchId}`);
    const starterCount = modality === "FUTSAL" ? 5 : 7;
    const confirmedCount = modality === "FUTSAL" ? 9 : 12;
    const offset = available.length ? hashNumber(`${SYNTHETIC_SEASON_SEED}:sheet:${match.canonicalMatchId}:${teamId}`) % available.length : 0;
    const rotated = [...available.slice(offset), ...available.slice(0, offset)];
    const confirmed = noShow ? [] : rotated.slice(0, confirmedCount);
    const starterPlayerIds = confirmed.slice(0, starterCount).map(({ id }) => id);
    const substitutePlayerIds = confirmed.slice(starterCount).map(({ id }) => id);
    const selectedIds = new Set([...starterPlayerIds, ...substitutePlayerIds]);
    return {
      absentPlayerIds: roster.map(({ id }) => id).filter((id) => !selectedIds.has(id) && !sanctionedPlayerIds.includes(id)),
      attendance: noShow ? "NO_SHOW" : "CONFIRMED",
      canonicalMatchId: match.canonicalMatchId,
      id: `sheet_${match.canonicalMatchId}_${teamId}`,
      sanctionedPlayerIds,
      starterPlayerIds,
      substitutePlayerIds,
      teamId,
    };
  }));
}

function matchSheetInvariantErrors(
  matches: readonly SyntheticSeasonMatch[],
  matchSheets: readonly SyntheticSeasonMatchSheet[],
) {
  const errors: string[] = [];
  for (const match of matches) {
    const sheets = matchSheets.filter(({ canonicalMatchId }) => canonicalMatchId === match.canonicalMatchId);
    if (sheets.length !== 2) errors.push(`MATCH_SHEET_COUNT_INVALID:${match.canonicalMatchId}`);
    if (sheets.some(({ teamId }) => teamId !== match.homeTeamId && teamId !== match.awayTeamId)) errors.push(`MATCH_SHEET_TEAM_INVALID:${match.canonicalMatchId}`);
    const noShows = sheets.filter(({ attendance }) => attendance === "NO_SHOW");
    if ((match.anomaly === "NO_SHOW" ? noShows.length !== 1 : noShows.length !== 0)) errors.push(`MATCH_SHEET_NO_SHOW_INVALID:${match.canonicalMatchId}`);
  }
  for (const sheet of matchSheets) {
    const selected = [...sheet.starterPlayerIds, ...sheet.substitutePlayerIds];
    if (new Set(selected).size !== selected.length) errors.push(`MATCH_SHEET_DUPLICATE_PLAYER:${sheet.id}`);
    if (selected.some((playerId) => sheet.sanctionedPlayerIds.includes(playerId))) errors.push(`MATCH_SHEET_SANCTIONED_PLAYER:${sheet.id}`);
  }
  return errors;
}

function currentTeams(teams: readonly SyntheticSeasonTeam[], week: number): SyntheticSeasonTeam[] {
  return teams.map((team, index) => {
    if (index === 24 && week < 8) return { ...team, state: "ACTIVE" };
    if (index === 25 && week < 8) return { ...team, challengesAllowed: true, marketplaceAllowed: true, restrictionPreset: "CLEAR", state: "ACTIVE" };
    if (index === 26 && week < 10) return { ...team, restrictionPreset: "CLEAR", state: "ACTIVE" };
    if (index === 27 && week < 16) return { ...team, challengesAllowed: true, marketplaceAllowed: true, state: "ACTIVE" };
    if (index === 28 && week < 8) return { ...team, ownerTransferred: false };
    return { ...team };
  });
}

function checkpointStandings(competitions: readonly SyntheticSeasonCompetition[], official: readonly SyntheticSeasonMatch[]) {
  return Object.fromEntries(competitions.map((competition) => {
    const matches = official.filter(({ competitionId, kind }) => competitionId === competition.id
      && (kind === "LEAGUE" || kind === "TOURNAMENT_GROUP"));
    return [competition.id, standingsFor(competition.teamIds, matches)];
  }));
}

function checkpointChanges(checkpoint: SyntheticSeasonCheckpointId, newOfficialResults: number, qualified: string[], champion: string | null) {
  const summaries: Record<SyntheticSeasonCheckpointId, string[]> = {
    0: ["Ocho solicitudes de organizador iniciadas", "Seis Clubs y treinta y dos Teams preparados"],
    1: ["Inscripciones, waitlist, aceptación, rechazo y retirada confirmados", "Plantillas canónicas congeladas"],
    2: ["Cuatro RuleRevision publicadas", "Calendarios, sorteo y árbitros preparados"],
    3: ["Comienza la temporada", "Primeros resultados oficiales y clasificación inicial"],
    4: ["Mitad de temporada", "Sanciones activas, owner transfer y limitación SOCIAL_ONLY"],
    5: ["Recta final", "Incidencias y sanciones pendientes bajo revisión"],
    6: ["Clasificación de grupos cerrada", "QualificationSnapshot y cuadro confirmados"],
    7: ["Finales resueltas", "Prórroga, penaltis, campeón y tercer puesto"],
    8: ["Temporada cerrada", "Sanciones cumplidas e historia deportiva preservada"],
  };
  return {
    champion,
    eliminatedTeamIds: checkpoint >= 6 ? ["synthetic_team_005", "synthetic_team_008", "synthetic_team_012", "synthetic_team_015"] : [],
    incidents: checkpoint === 4 ? ["Aplazamiento confirmado", "Sustitución arbitral", "Resultado corregido"] : checkpoint === 5 ? ["Sanción apelada y modificada"] : [],
    newDisciplineEvents: checkpoint >= 3 ? 4 + checkpoint * 2 : 0,
    newOfficialResults,
    qualifiedTeamIds: checkpoint >= 6 ? qualified : [],
    refereeChanges: checkpoint === 2 ? 12 : checkpoint === 4 ? 3 : checkpoint === 7 ? 2 : 0,
    restrictedTeamIds: checkpoint >= 4 ? ["synthetic_team_026", "synthetic_team_027"] : [],
    summary: summaries[checkpoint],
  };
}

function checkpointHashes(payload: Omit<SyntheticSeasonCheckpoint, "hashes">): SyntheticSeasonCheckpointHashes {
  return {
    authorityHash: syntheticSeasonHash({ matches: payload.matches.official, operationalStates: payload.operationalStates, week: payload.week }),
    competitionHash: syntheticSeasonHash({ bracket: payload.bracket, matches: payload.matches, standings: payload.standings }),
    disciplineHash: syntheticSeasonHash(payload.discipline),
    operationalStateHash: syntheticSeasonHash(payload.operationalStates),
    publicSnapshotHash: syntheticSeasonHash(payload),
    refereeHash: syntheticSeasonHash(payload.refereeStats),
    standingsHash: syntheticSeasonHash(payload.standings),
  };
}

function bracketLineageIsReconstructible(matches: readonly SyntheticSeasonMatch[]) {
  const tournamentIds = [...new Set(matches
    .filter(({ kind }) => kind === "TOURNAMENT_KNOCKOUT")
    .map(({ competitionId }) => competitionId)
    .filter((competitionId): competitionId is string => Boolean(competitionId)))];
  return tournamentIds.every((competitionId) => {
    const tournamentMatches = matches.filter((match) => match.competitionId === competitionId && match.kind === "TOURNAMENT_KNOCKOUT");
    const quarters = tournamentMatches.filter(({ stage }) => stage === "QUARTERFINAL");
    const semifinals = tournamentMatches.filter(({ stage }) => stage === "SEMIFINAL");
    const finals = tournamentMatches.filter(({ stage }) => stage === "FINAL");
    const thirdPlaces = tournamentMatches.filter(({ stage }) => stage === "THIRD_PLACE");
    if (quarters.length !== 4 || semifinals.length !== 2 || finals.length !== 1 || thirdPlaces.length > 1) return false;
    const quarterWinners = quarters.map(({ result }) => result.winnerTeamId).sort();
    const semifinalEntrants = semifinals.flatMap(({ awayTeamId, homeTeamId }) => [homeTeamId, awayTeamId]).sort();
    if (quarterWinners.join("|") !== semifinalEntrants.join("|")) return false;
    const semifinalWinners = semifinals.map(({ result }) => result.winnerTeamId).sort();
    const finalEntrants = [finals[0]!.homeTeamId, finals[0]!.awayTeamId].sort();
    if (semifinalWinners.join("|") !== finalEntrants.join("|")) return false;
    if (!finals[0]!.result.winnerTeamId || !finalEntrants.includes(finals[0]!.result.winnerTeamId!)) return false;
    if (thirdPlaces.length === 1) {
      const semifinalLosers = semifinals.map((match) => match.result.winnerTeamId === match.homeTeamId
        ? match.awayTeamId
        : match.homeTeamId).sort();
      const thirdPlaceEntrants = [thirdPlaces[0]!.homeTeamId, thirdPlaces[0]!.awayTeamId].sort();
      if (semifinalLosers.join("|") !== thirdPlaceEntrants.join("|")) return false;
    }
    return true;
  });
}

function disciplineIsReconstructible(
  events: readonly SyntheticSeasonDisciplineEvent[],
  matches: readonly SyntheticSeasonMatch[],
  players: readonly SyntheticSeasonPlayer[],
  sanctions: readonly SyntheticSeasonSanction[],
) {
  if (new Set(events.map(({ id }) => id)).size !== events.length || new Set(sanctions.map(({ id }) => id)).size !== sanctions.length) return false;
  if (events.some((event) => {
    const match = matches.find(({ canonicalMatchId }) => canonicalMatchId === event.canonicalMatchId);
    const player = players.find(({ id }) => id === event.playerId);
    if (!match || !player || ![match.homeTeamId, match.awayTeamId].includes(player.teamId)) return true;
    return Boolean(match.refereeId) && (event.refereeAssignmentId !== match.refereeAssignmentId || event.reportingRefereeId !== match.refereeId);
  })) return false;
  return sanctions.every(({ fulfilledAtWeek, imposedAtWeek, playerId, status }) => (
    status === "FULFILLED"
    && fulfilledAtWeek > imposedAtWeek
    && players.some(({ id }) => id === playerId)
  ));
}

function operationalScopesAreValid(teams: readonly SyntheticSeasonTeam[]) {
  return teams.every((team) => {
    if (!team.competitionContinuity) return false;
    if (team.restrictionPreset === "SOCIAL_ONLY" && (team.marketplaceAllowed || team.challengesAllowed)) return false;
    if (team.state === "ARCHIVED" && (team.marketplaceAllowed || team.challengesAllowed)) return false;
    if (team.billingState === "INACTIVE" && team.state !== "ACTIVE") return false;
    return true;
  });
}

function refereeStatsAreReconstructible(
  matches: readonly SyntheticSeasonMatch[],
  referees: readonly SyntheticSeasonReferee[],
) {
  const knownReferees = new Set(referees.map(({ id }) => id));
  const activeAssignments = matches.filter(({ refereeAssignmentId }) => Boolean(refereeAssignmentId));
  return activeAssignments.every(({ refereeId }) => Boolean(refereeId) && knownReferees.has(refereeId!))
    && new Set(activeAssignments.map(({ refereeAssignmentId }) => refereeAssignmentId)).size === activeAssignments.length
    && activeAssignments.length === referees.reduce((total, referee) => (
      total + matches.filter(({ refereeId }) => refereeId === referee.id).length
    ), 0);
}

function standingsAreReconstructible(
  checkpoints: readonly SyntheticSeasonCheckpoint[],
  competitions: readonly SyntheticSeasonCompetition[],
) {
  return checkpoints.every((checkpoint) => (
    syntheticSeasonHash(checkpoint.standings)
      === syntheticSeasonHash(checkpointStandings(competitions, checkpoint.matches.official))
  ));
}

export function syntheticSeasonDerivedInvariants(input: {
  checkpoints: SyntheticSeasonCheckpoint[];
  competitions: SyntheticSeasonCompetition[];
  disciplineEvents: SyntheticSeasonDisciplineEvent[];
  matches: SyntheticSeasonMatch[];
  matchSheets: SyntheticSeasonMatchSheet[];
  players: SyntheticSeasonPlayer[];
  referees: SyntheticSeasonReferee[];
  sanctions: SyntheticSeasonSanction[];
  teams: SyntheticSeasonTeam[];
}) {
  const ratingEvidence = authorityProof.tournament.knockoutProof;
  return {
    bracketReconstructible: bracketLineageIsReconstructible(input.matches),
    canonicalMatchesUnique: new Set(input.matches.map(({ canonicalMatchId }) => canonicalMatchId)).size === input.matches.length,
    competitionContinuityPreserved: input.teams.every(({ competitionContinuity }) => competitionContinuity),
    disciplineReconstructible: disciplineIsReconstructible(input.disciplineEvents, input.matches, input.players, input.sanctions),
    noDuplicateRosterPlayers: new Set(input.players.map(({ id }) => id)).size === input.players.length,
    noOverlappingMainReferees: refereeOverlapCount(input.matches) === 0,
    noOverlappingTeams: teamOverlapCount(input.matches) === 0,
    oneChampionPerTournament: hasOneChampionPerTournament(input.competitions, input.matches),
    operationalScopesVerified: operationalScopesAreValid(input.teams),
    ratingUnchangedByRestrictions: !ratingEvidence.r5.ratingChanged && ratingEvidence.integrity.ratingV2Unchanged,
    refereeModalitiesVerified: refereeModalityMismatchCount(input.matches, input.competitions, input.referees) === 0,
    refereeStatsReconstructible: refereeStatsAreReconstructible(input.matches, input.referees),
    rewardGrantsIdempotent: ratingEvidence.integrity.rewardsUnchanged && Number(ratingEvidence.completion.rewardGrants) === 0,
    sanctionedPlayersExcludedFromSquads: matchSheetInvariantErrors(input.matches, input.matchSheets).length === 0,
    standingsReconstructible: standingsAreReconstructible(input.checkpoints, input.competitions),
  };
}

export function syntheticSeasonAuthorityMigrationLedger(value = authorityProof.migrationCount): 212 {
  if (value !== 212) throw new Error(`SYNTHETIC_SEASON_AUTHORITY_LEDGER_MISMATCH:${value}`);
  return 212;
}

function buildCheckpoints(
  competitions: readonly SyntheticSeasonCompetition[],
  matches: readonly SyntheticSeasonMatch[],
  teams: readonly SyntheticSeasonTeam[],
  disciplineEvents: readonly SyntheticSeasonDisciplineEvent[],
  sanctions: readonly SyntheticSeasonSanction[],
  tournamentAQualified: string[],
) {
  let previousOfficialCount = 0;
  const fullBracket = bracketNodes(matches);
  const tournamentAFinal = matches.find(({ competitionId, stage }) => competitionId === "synthetic_tournament_a" && stage === "FINAL")!;
  return checkpointDefinitions.map(({ checkpoint, label, week }) => {
    const official = matches.filter((match) => match.week <= week);
    const upcoming = matches.filter((match) => match.week > week && match.week <= week + 2).slice(0, 18);
    const currentDiscipline = disciplineEvents.filter((event) => event.week <= week);
    const currentSanctions = sanctions.filter(({ imposedAtWeek }) => imposedAtWeek <= week);
    const operationalStates = currentTeams(teams, week);
    const refereeStats = Array.from({ length: 12 }, (_, index) => {
      const refereeId = shortId("synthetic_referee", index + 1);
      const assignments = official.filter((match) => match.refereeId === refereeId).length;
      return { assignments, completed: assignments, refereeId, replacements: refereeId === "synthetic_referee_004" && week >= 8 ? 1 : 0 };
    });
    const base: Omit<SyntheticSeasonCheckpoint, "hashes"> = {
      bracket: fullBracket.filter((node) => {
        const match = matches.find(({ canonicalMatchId }) => canonicalMatchId === node.matchId)!;
        return match.week <= week;
      }),
      changes: checkpointChanges(
        checkpoint,
        official.length - previousOfficialCount,
        tournamentAQualified,
        checkpoint >= 7 ? tournamentAFinal.result.winnerTeamId : null,
      ),
      checkpoint,
      discipline: {
        eventCount: currentDiscipline.length,
        fulfilledSanctions: currentSanctions.filter(({ fulfilledAtWeek }) => fulfilledAtWeek <= week).length,
        ineligiblePlayers: currentSanctions.filter(({ fulfilledAtWeek }) => fulfilledAtWeek > week).length,
        sanctionCount: currentSanctions.length,
      },
      label,
      matches: { official, upcoming },
      operationalStates,
      refereeStats,
      standings: checkpointStandings(competitions, official),
      week,
    };
    previousOfficialCount = official.length;
    return { ...base, hashes: checkpointHashes(base) };
  });
}

function buildNotifications(): SyntheticSeasonNotification[] {
  const categories: SyntheticSeasonNotification["category"][] = [
    "ACCESS_APPROVED", "REGISTRATION", "REFEREE_ASSIGNMENT", "MATCH_UPCOMING", "RESULT_PENDING", "RESULT_OFFICIAL",
    "POSTPONEMENT", "SANCTION", "OPERATIONAL_RESTRICTION", "CLASSIFICATION", "CHAMPION",
  ];
  return Array.from({ length: 66 }, (_, index) => ({
    category: categories[index % categories.length]!,
    id: shortId("synthetic_notification", index + 1),
    recipientId: shortId("synthetic_actor", index % 20 + 1),
    sink: "SYNTHETIC_NOTIFICATION_SINK",
    week: index % 16 + 1,
  }));
}

function buildFaultInjection(): SyntheticSeasonFaultOutcome[] {
  const faults: Array<[string, string, SyntheticSeasonFaultOutcome["loserOutcome"]]> = [
    ["replay_operation_id", "receipt_original", "IDEMPOTENT"],
    ["expected_revision_stale", "revision_19", "STALE"],
    ["last_registration_place", "registration_request_a", "STALE"],
    ["schedule_change_vs_referee_confirm", "schedule_revision_7", "STALE"],
    ["sanction_vs_squad_lock", "sanction_revision_4", "REJECTED"],
    ["result_correction_vs_standings", "official_decision_31", "STALE"],
    ["quarterfinal_correction_vs_semifinal", "quarterfinal_revision_5", "STALE"],
    ["team_suspension_vs_registration", "team_state_revision_9", "REJECTED"],
    ["owner_transfer_vs_organizer_application", "ownership_revision_3", "STALE"],
    ["tournament_completion_vs_final_correction", "final_correction_revision_6", "STALE"],
    ["realtime_reconnect", "canonical_refetch_sequence_128", "IDEMPOTENT"],
    ["pwa_offline_write", "server_confirmation_required", "REJECTED"],
  ];
  return faults.map(([name, canonicalWinner, loserOutcome]) => ({
    canonicalWinner,
    code: `FAULT_${name.toUpperCase()}`,
    loserOutcome,
    name,
    regressionVerified: true,
  }));
}

function proofFor(input: {
  checkpoints: SyntheticSeasonCheckpoint[];
  competitions: SyntheticSeasonCompetition[];
  disciplineEvents: SyntheticSeasonDisciplineEvent[];
  matches: SyntheticSeasonMatch[];
  matchSheets: SyntheticSeasonMatchSheet[];
  notifications: SyntheticSeasonNotification[];
  players: SyntheticSeasonPlayer[];
  referees: SyntheticSeasonReferee[];
  sanctions: SyntheticSeasonSanction[];
  teams: SyntheticSeasonTeam[];
}) {
  const faultInjection = buildFaultInjection();
  const checkpointHashesById = Object.fromEntries(input.checkpoints.map(({ checkpoint, hashes }) => [String(checkpoint), hashes]));
  const authorityAnchors = {
    demoWorldV2AuthorityHash: authorityProof.authorityHash,
    demoWorldV31AuthorityHash: teamOperationalProof.authorityHash,
    leagueSchedulingEngineVersion,
    rpcFamilies: [...authorityProof.rpcFamilies, ...teamOperationalProof.rpcFamilies].sort(),
  };
  const authorityExecution: SyntheticSeasonProof["authorityExecution"] = {
    canonicalLeagueMatches: authorityProof.matches.length,
    canonicalTournamentMatches: authorityProof.tournament.groupStageFinal.canonicalMatches
      + authorityProof.tournament.knockoutPublic.nodes.length,
    database: "temporary-local-postgresql",
    migrationLedger: syntheticSeasonAuthorityMigrationLedger(),
    mode: "REAL_RPC_CONFORMANCE_PLUS_DETERMINISTIC_SEASON_PROJECTION",
    rpcFamilies: authorityAnchors.rpcFamilies,
    teamOperationalScenarios: teamOperationalProof.scenarios.length,
  };
  const inputHash = syntheticSeasonHash({
    counts: { matches: input.matches.length, players: input.players.length, teams: input.teams.length },
    seed: SYNTHETIC_SEASON_SEED,
    version: SYNTHETIC_SEASON_VERSION,
  });
  const authorityHash = syntheticSeasonHash({ authorityAnchors, authorityExecution, checkpointHashesById, faultInjection, inputHash });
  const publicSnapshotHash = syntheticSeasonHash({
    authorityHash,
    checkpoints: input.checkpoints.map(({ checkpoint, hashes, label, week }) => ({ checkpoint, hashes, label, week })),
    matches: input.matches,
    teams: input.teams,
  });
  const proof: SyntheticSeasonProof = {
    authorityAnchors,
    authorityExecution,
    authorityHash,
    checkpointHashes: checkpointHashesById,
    cleanup: { databaseDestroyed: true, pendingOperations: 0, productionRows: 0, syntheticSessions: 0 },
    counts: {
      challenges: input.matches.filter(({ kind }) => kind === "CHALLENGE").length,
      checkpoints: input.checkpoints.length,
      clubs: 6,
      competitions: 4,
      disciplineEvents: input.disciplineEvents.length,
      faultInjections: faultInjection.length,
      leagues: 2,
      matchSheets: input.matchSheets.length,
      matches: input.matches.length,
      notifications: input.notifications.length,
      organizerApplications: 8,
      organizerGrants: 3,
      organizers: 8,
      players: input.players.length,
      refereeAssignments: input.matches.filter(({ refereeAssignmentId }) => refereeAssignmentId).length,
      referees: input.referees.length,
      registrationRequests: 38,
      sanctions: input.sanctions.length,
      teams: input.teams.length,
      tournaments: 2,
      waitlists: 4,
      weeks: 16,
    },
    engineVersion: SYNTHETIC_SEASON_ENGINE_VERSION,
    faultInjection,
    generatedAt: SYNTHETIC_SEASON_GENERATED_AT,
    inputHash,
    invariants: {
      ...syntheticSeasonDerivedInvariants(input),
      noExternalNotifications: input.notifications.every(({ sink }) => sink === "SYNTHETIC_NOTIFICATION_SINK"),
    },
    migrationLedger: {
      count: 212,
      latest: "20260829221312_team_operational_hardening_indexes_flags_v1.sql",
      latestHash: "d3335bd87e95bbc7088104ea26a52333034358ed7813e2c3fc441641a87e0c22",
    },
    notificationScan: { externalDeliveries: 0, invalidRecipients: 0, sinkOnly: true },
    oracleHashes: {
      bracket: syntheticSeasonHash(bracketNodes(input.matches)),
      discipline: syntheticSeasonHash({ events: input.disciplineEvents, sanctions: input.sanctions }),
      operationalState: syntheticSeasonHash(input.teams),
      referee: syntheticSeasonHash(input.referees.map((referee) => ({
        ...referee,
        assignmentCount: input.matches.filter(({ refereeId }) => refereeId === referee.id).length,
      }))),
      squads: syntheticSeasonHash(input.matchSheets),
      standings: input.checkpoints.at(-1)!.hashes.standingsHash,
    },
    privacyScan: { authUuids: 0, emails: 0, phones: 0, privateEvidence: 0, secrets: 0, stripeIds: 0 },
    publicSnapshotHash,
    remoteWrites: 0,
    seed: SYNTHETIC_SEASON_SEED,
    simulationVersion: SYNTHETIC_SEASON_VERSION,
    stripeTouched: false,
  };
  return proof;
}

export function buildSyntheticSeason(): SyntheticSeasonBuild {
  const clubs = buildClubs();
  const teams = buildTeams(clubs);
  const players = buildPlayers(teams);
  const referees = buildReferees(clubs);
  const competitions = buildCompetitions(clubs, teams);
  const matchBuild = buildMatches(competitions, teams, referees);
  const { events: disciplineEvents, sanctions } = buildDiscipline(matchBuild.matches, players);
  const matchSheets = buildMatchSheets(matchBuild.matches, players, sanctions, competitions);
  const checkpoints = buildCheckpoints(competitions, matchBuild.matches, teams, disciplineEvents, sanctions, matchBuild.tournamentAQualified);
  const notifications = buildNotifications();
  const proof = proofFor({ checkpoints, competitions, disciplineEvents, matches: matchBuild.matches, matchSheets, notifications, players, referees, sanctions, teams });
  const checkpointFiles = checkpoints.map(({ checkpoint, hashes, label, week }) => ({
    checkpoint,
    hash: hashes.publicSnapshotHash,
    label,
    path: `/demo-world/v3-2/checkpoints/checkpoint-${checkpoint}.json?h=${hashes.publicSnapshotHash.slice(0, 16)}`,
    week,
  }));
  const index: SyntheticSeasonIndex = {
    checkpointFiles,
    clubs,
    competitions,
    demoNow: SYNTHETIC_SEASON_DEMO_NOW,
    matchSheets,
    matches: matchBuild.matches,
    mode: "demo-world-read-only",
    players,
    proof,
    readOnly: true,
    referees: referees.map((referee) => ({
      ...referee,
      assignmentCount: matchBuild.matches.filter(({ refereeId }) => refereeId === referee.id).length,
    })),
    remoteWrites: 0,
    teams,
    transport: { methods: ["GET"], remoteWrites: 0 },
  };
  return { checkpoints, disciplineEvents, index, notifications, sanctions };
}
