import type { LeagueMatchOperationsJson } from "../league-match-operations-contract";

const ids = {
  awayEntry: "d4c00000-0000-4000-8000-000000000002",
  competition: "d4c00000-0000-4000-8000-000000000001",
  context: "d4c00000-0000-4000-8000-000000000003",
  homeEntry: "d4c00000-0000-4000-8000-000000000001",
  match: "d4c00000-0000-4000-8000-000000000004",
  round: "d4c00000-0000-4000-8000-000000000005",
  stage: "d4c00000-0000-4000-8000-000000000006",
};

function player(index: number, team: "home" | "away") {
  const suffix = String(team === "home" ? index : index + 20).padStart(12, "0");
  return {
    eligibilityStatus: "eligible",
    player: { displayName: `${team === "home" ? "Cobalto" : "Vértice"} ${index}` },
    playerProfileId: `d4c10000-0000-4000-8000-${suffix}`,
    rosterMemberId: `d4c20000-0000-4000-8000-${suffix}`,
  };
}

const homeRoster = Array.from({ length: 10 }, (_, index) => player(index + 1, "home"));
const awayRoster = Array.from({ length: 10 }, (_, index) => player(index + 1, "away"));

function squad(entryId: string, side: "HOME" | "AWAY", roster: ReturnType<typeof player>[], status = "locked") {
  return {
    currentRevisionId: `d4c30000-0000-4000-8000-${side === "HOME" ? "000000000001" : "000000000002"}`,
    entryId,
    id: `d4c40000-0000-4000-8000-${side === "HOME" ? "000000000001" : "000000000002"}`,
    members: roster.slice(0, 8).map((member, index) => ({
      captain: index === 0,
      player: member.player,
      playerProfileId: member.playerProfileId,
      positionOrder: index,
      role: index < 7 ? "STARTER" : "SUBSTITUTE",
      rosterMemberId: member.rosterMemberId,
    })),
    revision: 9,
    side,
    status,
  };
}

const baseMatch: LeagueMatchOperationsJson = {
  awayEntry: { id: ids.awayEntry, name: "Vértice Gràcia", teamId: "d4c50000-0000-4000-8000-000000000002" },
  competition: { id: ids.competition, name: "Liga Metropolitana QA", slug: "liga-metropolitana-qa", status: "active", type: "LEAGUE", visibility: "private" },
  competitionGroup: { id: "d4c60000-0000-4000-8000-000000000001", name: "Grupo A", status: "active" },
  context: {
    canonicalMatchId: ids.match,
    competitionId: ids.competition,
    disciplineValidationStatus: "NOT_AVAILABLE",
    id: ids.context,
    roundId: ids.round,
    ruleRevisionId: "d4c70000-0000-4000-8000-000000000001",
    scheduledEnd: "2027-03-20T20:30:00Z",
    scheduledStart: "2027-03-20T19:00:00Z",
    stageId: ids.stage,
    status: "scheduled",
    timezone: "Europe/Madrid",
    venueLabel: "Pista Demo Llevant",
    venueStatus: "CONFIRMED",
  },
  division: { id: "d4c80000-0000-4000-8000-000000000001", levelLabel: "Primera", name: "División 1", status: "active" },
  edition: { id: "d4c90000-0000-4000-8000-000000000001", name: "Edición 2027", seasonLabel: "2027", status: "active" },
  eligibleRoster: { away: awayRoster, home: homeRoster },
  flags: {
    attendanceEnabled: true,
    foundationEnabled: true,
    officialResultsEnabled: true,
    publicStandingsEnabled: true,
    resultConfirmationEnabled: true,
    sportingResultsEnabled: true,
    squadsEnabled: true,
    standingsEnabled: true,
  },
  homeEntry: { id: ids.homeEntry, name: "Cobalto Raval", teamId: "d4c50000-0000-4000-8000-000000000001" },
  kind: "LeagueCanonicalMatchView",
  nextValidActions: ["match.mark_ready"],
  permissions: { actorCompetitionRole: "competition_director", actorPlayerProfileId: homeRoster[0].playerProfileId, manageAway: false, manageHome: true, manageResults: true, manageStandings: true },
  revision: 18,
  round: { id: ids.round, name: "Jornada 3", number: 3, revision: 7, status: "published" },
  ruleRevision: { checksum: "a".repeat(64), id: "d4c70000-0000-4000-8000-000000000001", schemaVersion: "competition_rules.v1", status: "frozen", version: 4 },
  serverSequence: 4102,
  sportingResult: null,
  stage: { id: ids.stage, name: "Liga regular", status: "active", type: "LEAGUE_STAGE" },
  squads: [squad(ids.homeEntry, "HOME", homeRoster), squad(ids.awayEntry, "AWAY", awayRoster)],
  attendance: {
    awayClosedAt: null,
    homeClosedAt: null,
    players: [...homeRoster.slice(0, 8).map((member, index) => ({ ...member, entryId: ids.homeEntry, revision: 1, status: index < 7 ? "going" : "pending" })), ...awayRoster.slice(0, 8).map((member, index) => ({ ...member, entryId: ids.awayEntry, revision: 1, status: index < 6 ? "going" : index === 6 ? "not_going" : "pending" }))],
  },
};

export const leagueMatchOperationsFixtures = {
  match: baseMatch,
  result: {
    ...baseMatch,
    context: { ...baseMatch.context as object, status: "result_pending" },
    nextValidActions: ["sporting_result.accept", "sporting_result.propose_change", "sporting_result.dispute"],
    permissions: { ...baseMatch.permissions as object, manageAway: true },
    revision: 24,
    sportingResult: {
      confirmationPolicy: "BILATERAL",
      currentRevisionId: "d4ca0000-0000-4000-8000-000000000001",
      id: "d4cb0000-0000-4000-8000-000000000001",
      pendingResponseFromEntryId: ids.awayEntry,
      proposedByEntryId: ids.homeEntry,
      responseDeadline: "2027-03-22T19:00:00Z",
      responses: [],
      revision: 1,
      scoreAway: 2,
      scoreHome: 3,
      scorerDetailPolicy: "OPTIONAL",
      scorers: [
        { displayName: "Cobalto 4", entryId: ids.homeEntry, goals: 2, rosterMemberId: homeRoster[3].rosterMemberId },
        { displayName: "Cobalto 7", entryId: ids.homeEntry, goals: 1, rosterMemberId: homeRoster[6].rosterMemberId },
      ],
      state: "submitted",
    },
  } satisfies LeagueMatchOperationsJson,
  results: {
    competitionId: ids.competition,
    filter: null,
    flags: baseMatch.flags,
    kind: "LeagueResultDesk",
    matches: Array.from({ length: 9 }, (_, index) => ({
      awayEntry: { id: ids.awayEntry, name: index % 2 ? "Atlètic Marina" : "Vértice Gràcia" },
      canonicalMatchId: `d4cc0000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
      contextId: `d4cd0000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
      homeEntry: { id: ids.homeEntry, name: index % 3 ? "Cobalto Raval" : "Montjuïc 05" },
      matchStatus: index < 2 ? "result_pending" : index < 5 ? "official" : "played",
      nextAction: index < 2 ? "official_result.publish" : "wait_for_teams",
      officialOutcome: index < 5 && index >= 2 ? "MIRROR_SPORTING_RESULT" : null,
      revision: 10 + index,
      roundName: `Jornada ${index + 1}`,
      scheduledStart: `2027-0${Math.min(index + 2, 9)}-20T19:00:00Z`,
      scoreAway: index < 5 ? index % 3 : null,
      scoreHome: index < 5 ? (index + 1) % 4 : null,
      sportingState: index < 2 ? "disputed" : index < 5 ? "official" : null,
    })),
  } satisfies LeagueMatchOperationsJson,
  standings: {
    competitionId: ids.competition,
    flags: baseMatch.flags,
    health: "CURRENT",
    kind: "LeagueStandingsView",
    revision: 12,
    snapshot: {
      checksum: "b".repeat(64),
      computedResults: 15,
      criteria: ["POINTS", "HEAD_TO_HEAD_POINTS", "GOAL_DIFFERENCE", "GOALS_FOR", "PERSISTED_DRAW_LOT"],
      engineVersion: "league-standings-v1",
      explanations: [{ criterion: "HEAD_TO_HEAD_POINTS", explanation: "Cobalto supera a Vértice por puntos en sus enfrentamientos directos.", resolved: true, tieGroupKey: "c".repeat(64) }],
      generatedAt: "2027-05-20T22:15:00Z",
      id: "d4ce0000-0000-4000-8000-000000000001",
      rebuildKind: "INCREMENTAL",
      rows: ["Cobalto Raval", "Vértice Gràcia", "Atlètic Marina", "Montjuïc 05", "Sant Andreu City", "Besòs Nord"].map((name, index) => ({ adjustmentPoints: 0, basePoints: 24 - index * 3, draws: index % 2, effectivePoints: 24 - index * 3, entryId: `d4cf0000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`, goalDifference: 12 - index * 3, goalsAgainst: 8 + index, goalsFor: 20 - index * 2, losses: index, played: 10, position: index + 1, team: { name }, wins: 8 - index })),
      sourceRevision: 4910,
    },
    stageId: ids.stage,
  } satisfies LeagueMatchOperationsJson,
};
