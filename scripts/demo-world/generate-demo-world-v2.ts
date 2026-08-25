import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { DemoWorldPlayer, DemoWorldTeam } from "../../app/demo-world/demo-world-contract";
import {
  DEMO_WORLD_V2_SEED,
  DEMO_WORLD_V2_VERSION,
  assertDemoWorldV2Snapshot,
  computeDemoWorldV2Standings,
  type DemoWorldV2ClubsRefereesChunk,
  type DemoWorldV2CompetitionChunk,
  type DemoWorldV2LeagueEntry,
  type DemoWorldV2LeagueMatch,
  type DemoWorldV2Manifest,
  type DemoWorldV2Snapshot,
} from "../../app/demo-world/demo-world-v2-contract";
import { DEMO_WORLD_MODE, DEMO_WORLD_SEASON } from "../../app/demo-world/demo-world-contract";
import {
  loadDemoWorldV2AuthorityProof,
  type DemoWorldV2AuthorityProof,
  type DemoWorldV2AuthorityProofMatch,
} from "./demo-world-v2-authority";
import { generateDemoWorld } from "./generate-demo-world";

export const DEMO_WORLD_V2_NOW = "2027-03-18T18:00:00.000Z";
const DEMO_WORLD_V2_GENERATED_AT = "2026-08-25T10:00:00.000Z";
const LEAGUE_TEAM_IDS = [
  "demo_team_001",
  "demo_team_002",
  "demo_team_003",
  "demo_team_004",
  "demo_team_005",
  "demo_team_006",
] as const;

function hash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function id(scope: string, index?: number) {
  return `demo_league_${scope}${index === undefined ? "" : `_${String(index).padStart(3, "0")}`}`;
}

function addDays(iso: string, days: number) {
  const value = new Date(iso);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString();
}

function lineageLabel(type: DemoWorldV2AuthorityProofMatch["lineage"][number], match: DemoWorldV2AuthorityProofMatch) {
  switch (type) {
    case "postponement": return "Aplazamiento solicitado por el equipo local y aceptado por el rival";
    case "fixture_change": return match.exceptionType === "venue_changed"
      ? "Cambio de sede confirmado: Camp Municipal Besòs"
      : "Nueva fecha confirmada por la organización";
    case "suspension": return "Partido suspendido en el minuto 38 con marcador parcial";
    case "resumption": return "Reanudación sobre el mismo CanonicalMatch";
    case "official_result": return match.exceptionType === "no_show"
      ? "Incomparecencia confirmada: 3-0 reglamentario"
      : "Resultado oficial publicado";
  }
}

function scorersFor(
  goals: number,
  playerIds: readonly string[],
  side: "away" | "home",
) {
  if (!goals) return [];
  const totals = new Map<string, number>();
  for (let goal = 0; goal < goals; goal += 1) {
    const playerId = playerIds[goal % Math.min(3, playerIds.length)]!;
    totals.set(playerId, (totals.get(playerId) ?? 0) + 1);
  }
  return [...totals].map(([playerId, playerGoals]) => ({ goals: playerGoals, playerId, side }));
}

function rosterMember(entryId: string, player: DemoWorldPlayer, index: number) {
  return {
    eligibilityStatus: "eligible",
    player: { displayName: player.name, id: player.id, position: player.position.abbreviation },
    playerProfileId: player.id,
    rosterMemberId: `${entryId}_member_${String(index + 1).padStart(2, "0")}`,
  };
}

function buildMatchPreview(
  match: DemoWorldV2LeagueMatch,
  teamById: Map<string, DemoWorldTeam>,
  playerById: Map<string, DemoWorldPlayer>,
  entryById: Map<string, DemoWorldV2LeagueEntry>,
  rosterByEntry: Map<string, string[]>,
) {
  const homeEntry = entryById.get(match.homeEntryId)!;
  const awayEntry = entryById.get(match.awayEntryId)!;
  const homeTeam = teamById.get(match.homeTeamId)!;
  const awayTeam = teamById.get(match.awayTeamId)!;
  const homeRoster = (rosterByEntry.get(homeEntry.id) ?? []).map((playerId, index) => rosterMember(homeEntry.id, playerById.get(playerId)!, index));
  const awayRoster = (rosterByEntry.get(awayEntry.id) ?? []).map((playerId, index) => rosterMember(awayEntry.id, playerById.get(playerId)!, index));
  const squad = (entryId: string, side: "AWAY" | "HOME", roster: ReturnType<typeof rosterMember>[]) => ({
    entryId,
    id: `${match.id}_squad_${side.toLowerCase()}`,
    members: roster.slice(0, 10).map((member, index) => ({
      captain: index === 0,
      player: member.player,
      role: index < 7 ? "STARTER" : "SUBSTITUTE",
      rosterMemberId: member.rosterMemberId,
    })),
    side,
    status: "locked",
  });
  const attendancePlayers = [...homeRoster, ...awayRoster].map((member) => ({
    rosterMemberId: member.rosterMemberId,
    status: "going",
  }));
  return {
    attendance: {
      awayClosedAt: match.scheduledStart,
      homeClosedAt: match.scheduledStart,
      players: attendancePlayers,
    },
    awayEntry: { id: awayEntry.id, name: awayTeam.name, teamId: awayTeam.id },
    competition: { id: id("competition"), name: "LIGA BARRIOS IQ 2026/27" },
    context: {
      canonicalMatchId: match.canonicalMatchId,
      id: match.contextId,
      roundId: match.roundId,
      scheduledStart: match.scheduledStart,
      status: match.status,
      timezone: "Europe/Madrid",
      venueLabel: match.venueLabel,
    },
    edition: { id: id("edition"), name: "Temporada 2026/27", seasonLabel: DEMO_WORLD_SEASON },
    eligibleRoster: { away: awayRoster, home: homeRoster },
    flags: { foundationEnabled: true },
    homeEntry: { id: homeEntry.id, name: homeTeam.name, teamId: homeTeam.id },
    nextValidActions: [],
    officialResult: {
      outcome: match.officialDecision.outcome,
      publicExplanation: match.exceptionType === "no_show" ? "Incomparecencia confirmada tras el margen reglamentario." : "Resultado confirmado por la competición.",
      scoreAway: match.result.away,
      scoreHome: match.result.home,
    },
    permissions: {
      actorCompetitionRole: "viewer",
      actorPlayerProfileId: "",
      manageAway: false,
      manageHome: false,
      manageResults: false,
      manageStandings: false,
    },
    revision: match.officialDecision.revision,
    round: { id: match.roundId, name: `Jornada ${match.roundNumber}`, number: match.roundNumber, revision: 1 },
    ruleRevision: { id: id("rules"), status: "frozen", version: 1 },
    sportingResult: {
      confirmationPolicy: "BILATERAL",
      responses: [{ createdAt: match.officialDecision.publishedAt, entryId: awayEntry.id, kind: "ACCEPT" }],
      scoreAway: match.result.away,
      scoreHome: match.result.home,
      scorers: match.scorers,
      state: "official",
    },
    squads: [squad(homeEntry.id, "HOME", homeRoster), squad(awayEntry.id, "AWAY", awayRoster)],
    stage: { id: id("stage"), name: "Liga regular" },
  };
}

function buildCompetition(
  teams: DemoWorldTeam[],
  players: DemoWorldPlayer[],
  authorityProof: DemoWorldV2AuthorityProof,
): DemoWorldV2CompetitionChunk {
  const leagueTeams = LEAGUE_TEAM_IDS.map((teamId) => teams.find(({ id: candidate }) => candidate === teamId)!);
  const teamById = new Map(leagueTeams.map((team) => [team.id, team]));
  const playerById = new Map(players.map((player) => [player.id, player]));
  const entries = leagueTeams.map((team, index): DemoWorldV2LeagueEntry => ({
    id: id("entry", index + 1),
    rosterId: id("roster", index + 1),
    status: "accepted",
    teamId: team.id,
  }));
  const entryById = new Map(entries.map((entry) => [entry.id, entry]));
  const rosters = entries.map((entry) => ({
    entryId: entry.id,
    id: entry.rosterId,
    playerIds: players.filter(({ teamId }) => teamId === entry.teamId).map(({ id: playerId }) => playerId),
    status: "locked" as const,
  }));
  const rosterByEntry = new Map(rosters.map((roster) => [roster.entryId, roster.playerIds]));
  const matches: DemoWorldV2LeagueMatch[] = authorityProof.matches.map((proofMatch, index) => {
    const homeEntry = entries[proofMatch.homeEntryNumber - 1]!;
    const awayEntry = entries[proofMatch.awayEntryNumber - 1]!;
    const { away, home } = proofMatch.result;
    const homePlayers = rosterByEntry.get(homeEntry.id)!;
    const awayPlayers = rosterByEntry.get(awayEntry.id)!;
    const matchId = id("match", index + 1);
    const lineage = proofMatch.lineage.map((type, stepIndex) => ({
      at: type === "postponement" || type === "fixture_change"
        ? addDays(proofMatch.originalScheduledStart, type === "postponement" ? -5 : -4)
        : proofMatch.scheduledStart,
      id: `${matchId}_${type}_${stepIndex + 1}`,
      label: lineageLabel(type, proofMatch),
      sequence: stepIndex + 1,
      type,
    }));
    return {
      awayEntryId: awayEntry.id,
      awayTeamId: awayEntry.teamId,
      canonicalMatchId: id("canonical_match", index + 1),
      contextId: id("match_context", index + 1),
      exceptionType: proofMatch.exceptionType,
      homeEntryId: homeEntry.id,
      homeTeamId: homeEntry.teamId,
      id: matchId,
      lateArrivalStatus: proofMatch.lateArrivalStatus,
      lineage,
      officialDecision: {
        id: id("official_decision", index + 1),
        outcome: proofMatch.outcome,
        publishedAt: proofMatch.scheduledStart,
        revision: proofMatch.exceptionType === "none" ? 18 : 22,
      },
      originalScheduledStart: proofMatch.originalScheduledStart,
      partialResult: proofMatch.partialResult,
      result: proofMatch.result,
      roundId: id("round", proofMatch.roundNumber),
      roundNumber: proofMatch.roundNumber,
      scheduledStart: proofMatch.scheduledStart,
      scorers: [
        ...scorersFor(home, homePlayers, "home"),
        ...scorersFor(away, awayPlayers, "away"),
      ],
      status: "official",
      venueLabel: proofMatch.venueLabel,
    };
  });
  const rows = authorityProof.standings.map((row) => {
    const entry = entries[row.entryNumber - 1]!;
    const team = teamById.get(entry.teamId)!;
    return {
      draws: row.draws,
      effectivePoints: row.effectivePoints,
      entryId: entry.id,
      goalDifference: row.goalDifference,
      goalsAgainst: row.goalsAgainst,
      goalsFor: row.goalsFor,
      losses: row.losses,
      played: row.played,
      position: row.position,
      team: { displayName: team.name, id: team.id },
      teamId: team.id,
      wins: row.wins,
    };
  });
  const oracleRows = computeDemoWorldV2Standings(entries, matches, (teamId) => teamById.get(teamId)!.name);
  if (JSON.stringify(rows) !== JSON.stringify(oracleRows)) {
    throw new Error("DEMO_WORLD_V2_POSTGRES_STANDINGS_ORACLE_MISMATCH");
  }
  const rounds = Array.from({ length: authorityProof.roundCount }, (_, index) => ({
    id: id("round", index + 1),
    matchIds: matches.filter(({ roundNumber }) => roundNumber === index + 1).map(({ id: matchId }) => matchId),
    name: index === 0 ? "Jornada inaugural" : `Jornada ${index + 1}`,
    number: index + 1,
    status: "completed" as const,
  }));
  const schedulePreview = {
    competition: { id: id("competition"), name: "LIGA BARRIOS IQ 2026/27" },
    counts: { items: 15, rounds: 5 },
    nextValidActions: [],
    plan: { id: id("schedule_plan"), revision: 9, status: "published" },
    quality: { hardViolations: 0, softScore: 96, explanation: { preferences: { satisfied: 14, total: 15 } } },
    revision: { id: id("schedule_revision"), status: "published" },
    rounds: rounds.map((round) => ({
      id: round.id,
      name: round.name,
      number: round.number,
      status: round.status,
      fixtures: matches.filter(({ roundNumber }) => roundNumber === round.number).map((match) => ({
        awayTeam: teamById.get(match.awayTeamId)!.name,
        canonicalMatchId: match.canonicalMatchId,
        homeTeam: teamById.get(match.homeTeamId)!.name,
        id: match.id,
        startsAt: match.scheduledStart,
        status: match.status,
        timezone: "Europe/Madrid",
        venueLabel: match.venueLabel,
        venueStatus: "CONFIRMED",
      })),
    })),
  };
  const standingSnapshot = {
    checksum: hash({ matches: matches.map(({ canonicalMatchId, result }) => ({ canonicalMatchId, result })), rows }),
    computedResults: 15 as const,
    criteria: ["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR", "WINS"],
    id: id("standing_snapshot"),
    revision: 16,
    rows,
  };
  return {
    competition: {
      category: { id: id("category"), name: "Senior", sportFormat: "FOOTBALL_7", status: "active" },
      division: { id: id("division"), name: "División única", status: "active" },
      edition: { id: id("edition"), name: "Temporada 2026/27", seasonLabel: DEMO_WORLD_SEASON, status: "completed" },
      group: { id: id("group"), name: "Grupo A", status: "completed" },
      id: id("competition"),
      name: "LIGA BARRIOS IQ 2026/27",
      privateBeta: true,
      refereeAssignmentsEnabled: false,
      ruleRevision: { id: id("rules"), status: "frozen", version: 1 },
      slug: "liga-barrios-iq-2026-27",
      stage: { id: id("stage"), name: "Liga regular", status: "completed", type: "LEAGUE_STAGE" },
      status: "completed",
      visibility: "private",
    },
    delegates: entries.map((entry, index) => ({ entryId: entry.id, id: id("delegate", index + 1), role: "PRIMARY_DELEGATE", status: "active" })),
    entries,
    matchPreviews: Object.fromEntries(matches.map((match) => [match.id, buildMatchPreview(match, teamById, playerById, entryById, rosterByEntry)])),
    matches,
    provenance: {
      authorityHash: authorityProof.authorityHash,
      database: "temporary-local-postgresql",
      migrations: authorityProof.migrationCount,
      oracle: "independent-basic-standings-v1",
      rpcFamilies: ["R1", "R4A", "R4B", "R4C", "R4D"],
      source: "simulation-world",
      verified: true,
    },
    rosters,
    rounds,
    schedulePreview,
    standingSnapshot,
    standingsPreview: {
      health: "CURRENT",
      revision: standingSnapshot.revision,
      snapshot: {
        checksum: standingSnapshot.checksum,
        computedResults: standingSnapshot.computedResults,
        criteria: standingSnapshot.criteria,
        explanations: [],
        rows,
      },
      standingStateId: id("standing_state"),
    },
  };
}

function buildClubsReferees(teams: DemoWorldTeam[]): DemoWorldV2ClubsRefereesChunk {
  const refereeNames = [
    "Álex Serra", "Nora Vidal", "Dani Pons", "Marta Rius",
    "Hugo Ferrer", "Laia Bosch", "Nil Costa", "Carla Puig",
  ];
  const clubs = [
    {
      clubType: "FOOTBALL_CLUB" as const,
      description: "Club de barrio con dos equipos de fútbol 7 y actividad social estable.",
      generalArea: { countryCode: "ES" as const, municipality: "Barcelona", province: "Barcelona" },
      id: "demo_club_001",
      name: "Club Esportiu Raval IQ",
      refereeIds: ["demo_referee_001", "demo_referee_002", "demo_referee_003"],
      slug: "club-esportiu-raval-iq",
      teamIds: ["demo_team_001", "demo_team_002"],
      verified: true,
    },
    {
      clubType: "INDEPENDENT_ORGANIZER" as const,
      description: "Organización vecinal que conecta equipos de Sants y el Clot.",
      generalArea: { countryCode: "ES" as const, municipality: "Barcelona", province: "Barcelona" },
      id: "demo_club_002",
      name: "Barris en Joc",
      refereeIds: ["demo_referee_003", "demo_referee_004", "demo_referee_005"],
      slug: "barris-en-joc",
      teamIds: ["demo_team_003", "demo_team_004"],
      verified: true,
    },
    {
      clubType: "SPORTS_CENTER" as const,
      description: "Centro deportivo con campos, relaciones arbitrales y equipos asociados.",
      generalArea: { countryCode: "ES" as const, municipality: "Sant Andreu", province: "Barcelona" },
      id: "demo_club_003",
      name: "Centre Esportiu Besòs",
      refereeIds: ["demo_referee_006", "demo_referee_007", "demo_referee_008"],
      slug: "centre-esportiu-besos",
      teamIds: ["demo_team_005", "demo_team_006"],
      verified: false,
    },
  ].map((club) => ({
    ...club,
    publicProfile: {
      clubType: club.clubType,
      description: club.description,
      generalArea: club.generalArea,
      name: club.name,
      partner: club.id === "demo_club_001",
      slug: club.slug,
      teams: club.teamIds.map((teamId) => ({
        name: teams.find(({ id: candidate }) => candidate === teamId)!.name,
        relationshipType: "ASSOCIATED",
      })),
      verified: club.verified,
    },
  }));
  const referees = refereeNames.map((displayName, index) => ({
    availabilityStatus: index % 3 === 2 ? "LIMITED" as const : "AVAILABLE" as const,
    clubIds: clubs.filter(({ refereeIds }) => refereeIds.includes(`demo_referee_${String(index + 1).padStart(3, "0")}`)).map(({ id: clubId }) => clubId),
    displayName,
    id: `demo_referee_${String(index + 1).padStart(3, "0")}`,
    marketplaceStatus: "listed" as const,
    modalities: index % 2 === 0 ? ["FOOTBALL_7" as const, "FUTSAL" as const] : ["FOOTBALL_11" as const, "FOOTBALL_7" as const],
    municipality: index < 6 ? "Barcelona" : "Sant Andreu",
    publicBio: index % 2 === 0 ? "Arbitraje formativo y competiciones de barrio." : "Experiencia en ligas amateur y fútbol base.",
    slug: displayName.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, ""),
  }));
  return {
    clubs,
    refereeAssignmentsEnabled: false,
    referees,
    relationships: [
      ...clubs.flatMap((club) => club.teamIds.map((teamId, index) => ({ clubId: club.id, id: `${club.id}_team_${index + 1}`, status: "active" as const, teamId, type: "club_team" as const }))),
      ...clubs.flatMap((club) => club.refereeIds.map((refereeId, index) => ({ clubId: club.id, id: `${club.id}_referee_${index + 1}`, refereeId, status: "active" as const, type: "club_referee" as const }))),
    ],
  };
}

export function generateDemoWorldV2(
  authorityProof = loadDemoWorldV2AuthorityProof(),
): DemoWorldV2Snapshot {
  const v1 = generateDemoWorld();
  const competitions = buildCompetition(v1.core.teams, v1.players.players, authorityProof);
  const clubsReferees = buildClubsReferees(v1.core.teams);
  const activity = structuredClone(v1.activity);
  const core = structuredClone(v1.core);
  const matches = structuredClone(v1.matches);
  const players = structuredClone(v1.players);
  core.perspectives.push({
    id: "league-organizer",
    label: "Organizador de Liga",
    playerId: "demo_player_002",
    role: "admin",
    summary: "Consulta la competición y sus decisiones públicas sin alterar el snapshot.",
    teamId: "demo_team_001",
  });
  const payload = { activity, clubsReferees, competitions, core, matches, players };
  const snapshotHash = hash(payload);
  const cacheKey = snapshotHash.slice(0, 16);
  const manifest: DemoWorldV2Manifest = {
    chunks: {
      activity: `/demo-world/v2/activity.json?h=${cacheKey}`,
      clubsReferees: `/demo-world/v2/clubs-referees.json?h=${cacheKey}`,
      competitions: `/demo-world/v2/competitions.json?h=${cacheKey}`,
      core: `/demo-world/v2/core.json?h=${cacheKey}`,
      matches: `/demo-world/v2/matches.json?h=${cacheKey}`,
      players: `/demo-world/v2/players.json?h=${cacheKey}`,
    },
    counts: {
      achievements: activity.achievements.length,
      canonicalMatches: competitions.matches.length,
      challenges: matches.challenges.length,
      clubs: clubsReferees.clubs.length,
      competitions: 1,
      matches: matches.matches.length,
      notifications: activity.notifications.length,
      players: players.players.length,
      referees: clubsReferees.referees.length,
      rewardBoxes: activity.rewardBoxes.length,
      rounds: competitions.rounds.length,
      stories: core.stories.length,
      teams: core.teams.length,
    },
    demoNow: DEMO_WORLD_V2_NOW,
    generatedAt: DEMO_WORLD_V2_GENERATED_AT,
    hash: snapshotHash,
    mode: DEMO_WORLD_MODE,
    season: DEMO_WORLD_SEASON,
    seed: DEMO_WORLD_V2_SEED,
    version: DEMO_WORLD_V2_VERSION,
  };
  return assertDemoWorldV2Snapshot({ ...payload, manifest });
}

export async function writeDemoWorldV2(snapshot: DemoWorldV2Snapshot, outputDirectory: string) {
  await mkdir(outputDirectory, { recursive: true });
  const files = {
    "activity.json": snapshot.activity,
    "clubs-referees.json": snapshot.clubsReferees,
    "competitions.json": snapshot.competitions,
    "core.json": snapshot.core,
    "manifest.json": snapshot.manifest,
    "matches.json": snapshot.matches,
    "players.json": snapshot.players,
  };
  for (const [name, value] of Object.entries(files)) {
    await writeFile(path.join(outputDirectory, name), `${JSON.stringify(value)}\n`, "utf8");
  }
}

async function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  const outputDirectory = path.join(root, "public/demo-world/v2");
  const snapshot = generateDemoWorldV2();
  await writeDemoWorldV2(snapshot, outputDirectory);
  const payloadBytes = Buffer.byteLength(JSON.stringify({
    activity: snapshot.activity,
    clubsReferees: snapshot.clubsReferees,
    competitions: snapshot.competitions,
    core: snapshot.core,
    matches: snapshot.matches,
    players: snapshot.players,
  }));
  process.stdout.write(`${JSON.stringify({
    counts: snapshot.manifest.counts,
    hash: snapshot.manifest.hash,
    outputDirectory,
    payloadBytes,
  }, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
