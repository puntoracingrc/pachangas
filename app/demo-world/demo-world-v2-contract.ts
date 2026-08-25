import type { LeagueMatchOperationsJson } from "../league-match-operations-contract";
import type { LeagueSchedulingJson } from "../league-scheduling-contract";
import {
  disciplineArray,
  disciplineNumber,
  disciplineRecord,
  disciplineText,
  type CompetitionDisciplineJson,
} from "../competition-discipline-contract";
import {
  DEMO_WORLD_MODE,
  DEMO_WORLD_SEASON,
  demoWorldForbiddenPaths,
  demoWorldIntegrityErrors,
  type DemoWorldActivityChunk,
  type DemoWorldCoreChunk,
  type DemoWorldMatchesChunk,
  type DemoWorldPlayersChunk,
  type DemoWorldPrimaryTab,
  type DemoWorldSnapshot,
} from "./demo-world-contract";

export const DEMO_WORLD_V2_VERSION = 2.1 as const;
export const DEMO_WORLD_V2_SEED = "pachangas-iq-demo-world-v2-1-2026-27" as const;

export type DemoWorldV2PrimaryTab = DemoWorldPrimaryTab
  | "arbitros"
  | "clasificacion"
  | "club"
  | "disciplina"
  | "jornadas"
  | "liga";

export type DemoWorldV2Manifest = {
  chunks: {
    activity: string;
    clubsReferees: string;
    competitions: string;
    core: string;
    matches: string;
    players: string;
  };
  counts: {
    achievements: number;
    canonicalMatches: number;
    challenges: number;
    clubs: number;
    competitions: number;
    matches: number;
    notifications: number;
    players: number;
    referees: number;
    rewardBoxes: number;
    rounds: number;
    stories: number;
    teams: number;
  };
  demoNow: string;
  generatedAt: string;
  hash: string;
  mode: typeof DEMO_WORLD_MODE;
  season: typeof DEMO_WORLD_SEASON;
  seed: typeof DEMO_WORLD_V2_SEED;
  version: typeof DEMO_WORLD_V2_VERSION;
};

export type DemoWorldV2LeagueEntry = {
  id: string;
  rosterId: string;
  status: "accepted";
  teamId: string;
};

export type DemoWorldV2LeagueScorer = {
  goals: number;
  playerId: string;
  side: "away" | "home";
};

export type DemoWorldV2LineageStep = {
  at: string;
  id: string;
  label: string;
  sequence: number;
  type: "fixture_change" | "official_result" | "postponement" | "resumption" | "suspension";
};

export type DemoWorldV2LeagueMatch = {
  awayEntryId: string;
  awayTeamId: string;
  canonicalMatchId: string;
  contextId: string;
  exceptionType: "none" | "no_show" | "postponed" | "suspended_resumed" | "venue_changed";
  homeEntryId: string;
  homeTeamId: string;
  id: string;
  lateArrivalStatus: "arrived_within_policy" | null;
  lineage: DemoWorldV2LineageStep[];
  officialDecision: {
    id: string;
    outcome: "MIRROR_SPORTING_RESULT" | "NO_SHOW";
    publishedAt: string;
    revision: number;
  };
  originalScheduledStart: string;
  partialResult: { away: number; home: number; minute: number } | null;
  result: { away: number; home: number };
  roundId: string;
  roundNumber: number;
  scheduledStart: string;
  scorers: DemoWorldV2LeagueScorer[];
  status: "official";
  venueLabel: string;
};

export type DemoWorldV2StandingRow = {
  draws: number;
  effectivePoints: number;
  entryId: string;
  goalDifference: number;
  goalsAgainst: number;
  goalsFor: number;
  losses: number;
  played: number;
  position: number;
  team: { displayName: string; id: string };
  teamId: string;
  wins: number;
};

export type DemoWorldV2CompetitionChunk = {
  competition: {
    category: { id: string; name: string; sportFormat: "FOOTBALL_7"; status: "active" };
    division: { id: string; name: string; status: "active" };
    edition: { id: string; name: string; seasonLabel: typeof DEMO_WORLD_SEASON; status: "completed" };
    group: { id: string; name: string; status: "completed" };
    id: string;
    name: "LIGA BARRIOS IQ 2026/27";
    privateBeta: true;
    refereeAssignmentsEnabled: false;
    ruleRevision: { id: string; status: "frozen"; version: 1 };
    slug: "liga-barrios-iq-2026-27";
    stage: { id: string; name: string; status: "completed"; type: "LEAGUE_STAGE" };
    status: "completed";
    visibility: "private";
  };
  delegates: Array<{ entryId: string; id: string; role: "PRIMARY_DELEGATE"; status: "active" }>;
  disciplinePreview: CompetitionDisciplineJson;
  entries: DemoWorldV2LeagueEntry[];
  matchPreviews: Record<string, LeagueMatchOperationsJson>;
  matchDisciplinePreviews: Record<string, CompetitionDisciplineJson>;
  matches: DemoWorldV2LeagueMatch[];
  provenance: {
    authorityHash: string;
    database: "temporary-local-postgresql";
    migrations: number;
    oracle: "independent-basic-standings-v1";
    rpcFamilies: ["R1", "R4A", "R4B", "R4C", "R4D", "R5"];
    source: "simulation-world";
    verified: true;
  };
  rosters: Array<{ entryId: string; id: string; playerIds: string[]; status: "locked" }>;
  rounds: Array<{ id: string; matchIds: string[]; name: string; number: number; status: "completed" }>;
  schedulePreview: LeagueSchedulingJson;
  standingSnapshot: {
    checksum: string;
    computedResults: 15;
    criteria: string[];
    id: string;
    revision: number;
    rows: DemoWorldV2StandingRow[];
  };
  standingsPreview: LeagueMatchOperationsJson;
};

export type DemoWorldV2Club = {
  clubType: "FOOTBALL_CLUB" | "INDEPENDENT_ORGANIZER" | "SPORTS_CENTER";
  description: string;
  generalArea: { countryCode: "ES"; municipality: string; province: string };
  id: string;
  name: string;
  publicProfile: Record<string, unknown>;
  refereeIds: string[];
  slug: string;
  teamIds: string[];
  verified: boolean;
};

export type DemoWorldV2Referee = {
  availabilityStatus: "AVAILABLE" | "LIMITED";
  clubIds: string[];
  displayName: string;
  id: string;
  marketplaceStatus: "listed";
  modalities: Array<"FOOTBALL_11" | "FOOTBALL_7" | "FUTSAL">;
  municipality: string;
  publicBio: string;
  slug: string;
};

export type DemoWorldV2ClubsRefereesChunk = {
  clubs: DemoWorldV2Club[];
  refereeAssignmentsEnabled: false;
  referees: DemoWorldV2Referee[];
  relationships: Array<{
    clubId: string;
    id: string;
    refereeId?: string;
    status: "active";
    teamId?: string;
    type: "club_referee" | "club_team";
  }>;
};

export type DemoWorldV2Snapshot = {
  activity: DemoWorldActivityChunk;
  clubsReferees: DemoWorldV2ClubsRefereesChunk;
  competitions: DemoWorldV2CompetitionChunk;
  core: DemoWorldCoreChunk;
  manifest: DemoWorldV2Manifest;
  matches: DemoWorldMatchesChunk;
  players: DemoWorldPlayersChunk;
};

export function computeDemoWorldV2Standings(
  entries: readonly DemoWorldV2LeagueEntry[],
  matches: readonly DemoWorldV2LeagueMatch[],
  teamName: (teamId: string) => string,
): DemoWorldV2StandingRow[] {
  const rows = new Map(entries.map((entry) => [entry.id, {
    draws: 0,
    effectivePoints: 0,
    entryId: entry.id,
    goalDifference: 0,
    goalsAgainst: 0,
    goalsFor: 0,
    losses: 0,
    played: 0,
    position: 0,
    team: { displayName: teamName(entry.teamId), id: entry.teamId },
    teamId: entry.teamId,
    wins: 0,
  }]));
  for (const match of matches) {
    const home = rows.get(match.homeEntryId);
    const away = rows.get(match.awayEntryId);
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
      home.effectivePoints += 1;
      away.effectivePoints += 1;
    } else if (match.result.home > match.result.away) {
      home.wins += 1;
      away.losses += 1;
      home.effectivePoints += 3;
    } else {
      away.wins += 1;
      home.losses += 1;
      away.effectivePoints += 3;
    }
  }
  return [...rows.values()]
    .map((row) => ({ ...row, goalDifference: row.goalsFor - row.goalsAgainst }))
    .sort((left, right) => right.effectivePoints - left.effectivePoints
      || right.goalDifference - left.goalDifference
      || right.goalsFor - left.goalsFor
      || right.wins - left.wins
      || left.team.displayName.localeCompare(right.team.displayName, "es"))
    .map((row, index) => ({ ...row, position: index + 1 }));
}

export function demoWorldV2IntegrityErrors(snapshot: DemoWorldV2Snapshot): string[] {
  const errors = demoWorldIntegrityErrors(snapshot as unknown as DemoWorldSnapshot);
  const competition = snapshot.competitions;
  const teamIds = new Set(snapshot.core.teams.map(({ id }) => id));
  const playerIds = new Set(snapshot.players.players.map(({ id }) => id));
  const entryIds = new Set(competition.entries.map(({ id }) => id));
  const roundIds = new Set(competition.rounds.map(({ id }) => id));
  const canonicalIds = new Set<string>();

  if (competition.entries.length !== 6) errors.push("League must have exactly 6 entries");
  if (competition.delegates.length !== 6) errors.push("League must have exactly 6 delegates");
  if (competition.rosters.length !== 6) errors.push("League must have exactly 6 rosters");
  if (competition.rounds.length !== 5) errors.push("League must have exactly 5 rounds");
  if (competition.matches.length !== 15) errors.push("League must have exactly 15 canonical matches");
  if (snapshot.clubsReferees.clubs.length < 3) errors.push("Demo World V2 requires at least 3 clubs");
  if (snapshot.clubsReferees.referees.length < 8) errors.push("Demo World V2 requires at least 8 referees");
  if (snapshot.clubsReferees.refereeAssignmentsEnabled) errors.push("Referee assignments must remain disabled");

  const discipline = competition.disciplinePreview;
  const disciplineEvents = disciplineArray(discipline.events);
  const disciplineSanctions = disciplineArray(discipline.sanctions);
  const disciplineService = disciplineArray(discipline.serviceEvents);
  const disciplineCards = disciplineEvents.reduce<Record<string, number>>((counts, event) => {
    const code = disciplineText(event.cardTypeCode);
    counts[code] = (counts[code] ?? 0) + 1;
    return counts;
  }, {});
  if (disciplineEvents.length !== 20 || disciplineCards.YELLOW !== 16
      || disciplineCards.RED !== 2 || disciplineCards.BLUE !== 2) {
    errors.push("Demo World V2.1 discipline card distribution is invalid");
  }
  if (disciplineSanctions.length !== 4 || disciplineService.length !== 2) {
    errors.push("Demo World V2.1 discipline sanctions or service history are invalid");
  }
  const eligibility = disciplineArray(discipline.eligibilityTimeline);
  if (JSON.stringify(eligibility.map((item) => disciplineText(item.selectedSlot)))
      !== JSON.stringify(["primary", "primary", "primary", "alternate", "primary"])) {
    errors.push("Demo World V2.1 eligibility chronology is invalid");
  }
  if (disciplineNumber(disciplineRecord(discipline.health).pendingAppeals) !== 0
      || disciplineArray(discipline.appeals).length !== 0) {
    errors.push("Public Demo discipline must not expose appeal records");
  }

  for (const entry of competition.entries) {
    if (!teamIds.has(entry.teamId)) errors.push(`Unknown League team ${entry.teamId}`);
    const roster = competition.rosters.find(({ entryId, id }) => id === entry.rosterId && entryId === entry.id);
    if (!roster) errors.push(`Missing roster for ${entry.id}`);
  }
  for (const roster of competition.rosters) {
    for (const playerId of roster.playerIds) if (!playerIds.has(playerId)) errors.push(`Unknown roster player ${playerId}`);
  }
  for (const match of competition.matches) {
    if (!entryIds.has(match.homeEntryId) || !entryIds.has(match.awayEntryId)) errors.push(`Unknown entry in ${match.id}`);
    if (!roundIds.has(match.roundId)) errors.push(`Unknown round in ${match.id}`);
    if (canonicalIds.has(match.canonicalMatchId)) errors.push(`Duplicate CanonicalMatch ${match.canonicalMatchId}`);
    canonicalIds.add(match.canonicalMatchId);
    const homeGoals = match.scorers.filter(({ side }) => side === "home").reduce((sum, scorer) => sum + scorer.goals, 0);
    const awayGoals = match.scorers.filter(({ side }) => side === "away").reduce((sum, scorer) => sum + scorer.goals, 0);
    if (homeGoals !== match.result.home || awayGoals !== match.result.away) errors.push(`Scorer mismatch in ${match.id}`);
    for (const scorer of match.scorers) if (!playerIds.has(scorer.playerId)) errors.push(`Unknown scorer ${scorer.playerId}`);
    const matchDiscipline = competition.matchDisciplinePreviews[match.id];
    if (!matchDiscipline) errors.push(`Missing discipline preview for ${match.id}`);
    else if (disciplineArray(matchDiscipline.events).some((event) => disciplineText(event.canonicalMatchId) !== match.canonicalMatchId)) {
      errors.push(`Discipline event belongs to another match in ${match.id}`);
    }
  }
  for (const round of competition.rounds) {
    if (round.matchIds.length !== 3) errors.push(`${round.id} must contain 3 matches`);
    for (const matchId of round.matchIds) if (!competition.matches.some(({ id }) => id === matchId)) errors.push(`Unknown round match ${matchId}`);
  }
  const oracle = computeDemoWorldV2Standings(
    competition.entries,
    competition.matches,
    (teamId) => snapshot.core.teams.find(({ id }) => id === teamId)?.name ?? teamId,
  );
  if (JSON.stringify(oracle) !== JSON.stringify(competition.standingSnapshot.rows)) {
    errors.push("StandingSnapshot differs from the independent oracle");
  }
  const forbidden = demoWorldForbiddenPaths({ clubsReferees: snapshot.clubsReferees, competitions: snapshot.competitions });
  errors.push(...forbidden.map((path) => `Forbidden public field: ${path}`));
  return [...new Set(errors)];
}

export function assertDemoWorldV2Snapshot(snapshot: DemoWorldV2Snapshot) {
  if (snapshot.manifest.version !== DEMO_WORLD_V2_VERSION) throw new Error("Unsupported Demo World V2 version");
  if (snapshot.manifest.seed !== DEMO_WORLD_V2_SEED) throw new Error("Unexpected Demo World V2 seed");
  if (snapshot.manifest.mode !== DEMO_WORLD_MODE) throw new Error("Demo World V2 is not read-only");
  const errors = demoWorldV2IntegrityErrors(snapshot);
  if (errors.length) throw new Error(`Invalid Demo World V2 snapshot:\n${errors.join("\n")}`);
  return snapshot;
}
