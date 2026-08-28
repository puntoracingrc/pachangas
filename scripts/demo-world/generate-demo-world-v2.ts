import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { DemoWorldPlayer, DemoWorldTeam } from "../../app/demo-world/demo-world-contract";
import type { CompetitionDisciplineJson } from "../../app/competition-discipline-contract";
import {
  DEMO_WORLD_V2_SEED,
  DEMO_WORLD_V2_VERSION,
  assertDemoWorldV2Snapshot,
  computeDemoWorldV2Standings,
  type DemoWorldV2ClubsRefereesChunk,
  type DemoWorldV2CompetitionChunk,
  type DemoWorldV2ConfigurationChunk,
  type DemoWorldV2LeagueEntry,
  type DemoWorldV2LeagueMatch,
  type DemoWorldV2Manifest,
  type DemoWorldV2Snapshot,
  type DemoWorldV2TournamentChunk,
  type DemoWorldV2TournamentOutcome,
} from "../../app/demo-world/demo-world-v2-contract";
import { DEMO_WORLD_MODE, DEMO_WORLD_SEASON } from "../../app/demo-world/demo-world-contract";
import {
  loadDemoWorldV2AuthorityProof,
  type DemoWorldV2AuthorityProof,
  type DemoWorldV2AuthorityProofMatch,
  type DemoWorldV2AuthorityProofPlayerRef,
} from "./demo-world-v2-authority";
import { generateDemoWorld } from "./generate-demo-world";

export const DEMO_WORLD_V2_NOW = "2027-03-18T18:00:00.000Z";
const DEMO_WORLD_V2_GENERATED_AT = "2026-08-27T14:00:00.000Z";
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
      ? "Cambio de sede confirmado: Camp Municipal Besòs · Barcelona"
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

function buildRefereeAssignmentPreviews(
  authorityProof: DemoWorldV2AuthorityProof,
  matches: DemoWorldV2LeagueMatch[],
  teamById: Map<string, DemoWorldTeam>,
) {
  const assignmentIdByKey = new Map(authorityProof.refereeAssignments.assignments.map((assignment, index) => [
    assignment.assignmentKey,
    id("referee_assignment", index + 1),
  ]));
  const profiles = new Map(authorityProof.refereeAssignments.profiles.map((profile) => [profile.refereeNumber, profile]));
  const items = authorityProof.refereeAssignments.assignments.map((assignment) => {
    const match = matches[assignment.matchOrdinal - 1]!;
    const referee = profiles.get(assignment.refereeNumber)!;
    return {
      assignmentRole: "MAIN_REFEREE",
      canonicalMatchId: match.canonicalMatchId,
      competitionId: id("competition"),
      competitionMatchContextId: match.contextId,
      competitionName: "LIGA BARRIOS IQ 2026/27",
      effectiveScheduledEnd: assignment.effectiveScheduledEnd,
      effectiveScheduledStart: assignment.effectiveScheduledStart,
      effectiveTimezone: "Europe/Madrid",
      id: assignmentIdByKey.get(assignment.assignmentKey)!,
      matchTitle: `${teamById.get(match.homeTeamId)!.name} · ${teamById.get(match.awayTeamId)!.name}`,
      modality: "FOOTBALL_7",
      reconfirmed: assignment.reconfirmed,
      referee: {
        displayName: referee.displayName,
        id: `demo_referee_${String(referee.refereeNumber).padStart(3, "0")}`,
        slug: referee.slug,
      },
      refereeProfileId: `demo_referee_${String(referee.refereeNumber).padStart(3, "0")}`,
      replacedByAssignmentId: assignment.replacedByAssignmentKey
        ? assignmentIdByKey.get(assignment.replacedByAssignmentKey) ?? null
        : null,
      replacesAssignmentId: assignment.replacesAssignmentKey
        ? assignmentIdByKey.get(assignment.replacesAssignmentKey) ?? null
        : null,
      requesterCompetitionId: id("competition"),
      requesterKind: "COMPETITION",
      requesterName: "Organizacion Liga Barrios IQ",
      revision: assignment.revision,
      scheduleState: assignment.scheduleState,
      scheduledEnd: assignment.scheduledEnd,
      scheduledStart: assignment.scheduledStart,
      sourceId: match.contextId,
      sourceKind: "competition_generated",
      status: assignment.status,
      timezone: "Europe/Madrid",
      venueLabel: match.venueLabel,
    };
  });
  const summary = {
    accepted: items.filter(({ status }) => status === "accepted").length,
    cancelled: items.filter(({ status }) => status === "cancelled").length,
    completed: items.filter(({ status }) => status === "completed").length,
    confirmed: items.filter(({ status }) => status === "confirmed").length,
    declined: items.filter(({ status }) => status === "declined").length,
    pending: items.filter(({ status }) => status === "proposed").length,
    reconfirmationRequired: items.filter(({ scheduleState }) => scheduleState === "RECONFIRMATION_REQUIRED").length,
    replaced: items.filter(({ status }) => status === "replaced").length,
  };
  const deskMatches = matches.map((match) => ({
    assignments: items.filter((assignment) => assignment.canonicalMatchId === match.canonicalMatchId),
    canonicalMatchId: match.canonicalMatchId,
    competitionMatchContextId: match.contextId,
    effectiveScheduledStart: match.scheduledStart,
    effectiveTimezone: "Europe/Madrid",
    venueLabel: match.venueLabel,
  }));
  const base = {
    capabilities: { manage: false, read: true },
    flags: { assignmentPrivateBetaEnabled: true, assignmentsEnabled: true },
    items,
    matches: deskMatches,
    revision: authorityProof.operationReceipts.refereeAssignments,
    summary,
  };
  return {
    desk: base,
    perMatch: Object.fromEntries(matches.map((match) => [match.id, {
      capabilities: { manage: false, read: true },
      flags: base.flags,
      items: items.filter((assignment) => assignment.canonicalMatchId === match.canonicalMatchId),
      revision: base.revision,
      summary,
    }])),
  };
}

function buildDisciplinePreviews(
  authorityProof: DemoWorldV2AuthorityProof,
  entries: DemoWorldV2LeagueEntry[],
  matches: DemoWorldV2LeagueMatch[],
  playerById: Map<string, DemoWorldPlayer>,
  rosterByEntry: Map<string, string[]>,
) {
  const discipline = authorityProof.discipline;
  const refereeAssignmentIdByKey = new Map(authorityProof.refereeAssignments.assignments.map((assignment, index) => [
    assignment.assignmentKey,
    id("referee_assignment", index + 1),
  ]));
  const playerFor = (reference: DemoWorldV2AuthorityProofPlayerRef) => {
    const entry = entries[reference.entryNumber - 1]!;
    const roster = rosterByEntry.get(entry.id) ?? [];
    const playerId = roster[reference.playerSlot === "alternate" ? 1 : 0] ?? roster[0]!;
    return { entry, player: playerById.get(playerId)! };
  };
  const eventIdByKey = new Map(discipline.events.map((event, index) => [
    event.eventKey,
    id("discipline_event", index + 1),
  ]));
  const sanctionIdByKey = new Map(discipline.sanctions.map((sanction, index) => [
    sanction.sourceEventKey,
    id("sanction", index + 1),
  ]));
  const sanctions = discipline.sanctions.map((sanction) => {
    const { entry, player } = playerFor(sanction);
    return {
      canAppeal: false,
      cycleId: id("discipline_cycle"),
      entryId: entry.id,
      id: sanctionIdByKey.get(sanction.sourceEventKey)!,
      outcome: sanction.outcome,
      playerProfileId: player.id,
      publicReasonCategory: sanction.publicReasonCategory,
      publicSummary: sanction.publicSummary,
      remainingUnits: sanction.remainingUnits,
      revision: sanction.status === "served" ? 4 : 2,
      sourceEventId: eventIdByKey.get(sanction.sourceEventKey)!,
      status: sanction.status,
      targetType: "PLAYER",
      totalUnits: sanction.totalUnits,
      unitType: sanction.unitType,
    };
  });
  const sanctionByEventKey = new Map(sanctions.map((sanction) => [
    discipline.sanctions.find((candidate) => eventIdByKey.get(candidate.sourceEventKey) === sanction.sourceEventId)!.sourceEventKey,
    sanction,
  ]));
  const events = discipline.events.map((event) => {
    const { entry, player } = playerFor(event);
    const match = matches[event.matchOrdinal - 1]!;
    const sanction = sanctionByEventKey.get(event.eventKey);
    return {
      canonicalMatchId: match.canonicalMatchId,
      cardTypeCode: event.cardTypeCode,
      context: event.context,
      cycleId: id("discipline_cycle"),
      entryId: entry.id,
      id: eventIdByKey.get(event.eventKey)!,
      label: event.cardTypeCode === "YELLOW" ? "Amarilla" : event.cardTypeCode === "RED" ? "Roja" : "Azul",
      matchContextId: match.contextId,
      minute: event.minute,
      playerDisplay: { displayName: player.name },
      playerProfileId: player.id,
      publicReasonCategory: event.publicReasonCategory,
      publicSummary: event.publicSummary,
      refereeAssignmentId: event.refereeAssignmentKey
        ? refereeAssignmentIdByKey.get(event.refereeAssignmentKey) ?? null
        : null,
      reportingRefereeProfileId: event.reportingRefereeNumber
        ? `demo_referee_${String(event.reportingRefereeNumber).padStart(3, "0")}`
        : null,
      revision: event.revisionVersion,
      revisionVersion: event.revisionVersion,
      sanction: sanction ? {
        id: sanction.id,
        outcome: sanction.outcome,
        remainingUnits: sanction.remainingUnits,
        status: sanction.status,
        unitType: sanction.unitType,
      } : null,
      status: event.status,
      temporaryDismissal: event.temporaryDismissal,
      visualType: event.visualType,
    };
  });
  const serviceEvents = discipline.serviceEvents.map((service, index) => ({
    canonicalMatchId: matches[service.matchOrdinal - 1]!.canonicalMatchId,
    createdAt: addDays(DEMO_WORLD_V2_GENERATED_AT, index + 1),
    eventType: service.eventType,
    id: id("sanction_service", index + 1),
    remainingAfter: service.remainingAfter,
    remainingBefore: service.remainingBefore,
    reversesServiceEventId: null,
    sanctionId: sanctionIdByKey.get(service.sourceEventKey)!,
    units: service.units,
  }));
  const counters = discipline.counters.map((counter, index) => {
    const { player } = playerFor(counter);
    return {
      cardTypeCode: counter.cardTypeCode,
      eventCount: counter.eventCount,
      id: id("discipline_counter", index + 1),
      playerProfileId: player.id,
      points: counter.points,
      thresholdHits: counter.thresholdHits,
    };
  });
  const playerStates = discipline.playerStates.map((state, index) => {
    const { entry, player } = playerFor(state);
    return {
      cards: state.cards,
      cycleId: id("discipline_cycle"),
      display: { displayName: player.name },
      entryId: entry.id,
      id: id("discipline_player_state", index + 1),
      playerProfileId: player.id,
      remainingUnits: state.remainingUnits,
      revision: 1,
      status: state.status,
      unitType: state.unitType,
    };
  });
  const flags = {
    appealsEnabled: true,
    countersEnabled: true,
    engineVersion: "competition-discipline-v1",
    eventsEnabled: true,
    foundationEnabled: true,
    publicEnabled: false,
    sanctionsEnabled: true,
    serviceEnabled: true,
  };
  const base: CompetitionDisciplineJson = {
    appeals: [],
    competitionId: id("competition"),
    counters,
    cycles: [{ id: id("discipline_cycle"), scopeType: "EDITION", status: "active" }],
    eligibilityTimeline: discipline.eligibilityTimeline,
    events,
    flags,
    health: {
      activeSanctions: sanctions.filter(({ status }) => ["active", "provisional", "under_review"].includes(status)).length,
      counterRows: counters.length,
      latestServerSequence: authorityProof.operationReceipts.discipline,
      pendingAppeals: 0,
    },
    matchContext: {},
    matchPlayers: [],
    permissions: { manage: false, manageAppeals: false, read: true, review: false },
    playerStates,
    revision: authorityProof.operationReceipts.discipline,
    ruleCatalog: {
      cardTypes: [
        { code: "YELLOW", label: "Amarilla", visualType: "yellow" },
        { code: "RED", label: "Roja", visualType: "red" },
        { code: "BLUE", label: "Azul", visualType: "blue" },
      ],
      policyVersion: "competition-discipline-v1",
    },
    sanctions,
    serviceEvents,
  };
  const matchDisciplinePreviews = Object.fromEntries(matches.map((match) => {
    const matchEvents = events.filter((event) => event.canonicalMatchId === match.canonicalMatchId);
    const eventIds = new Set(matchEvents.map((event) => event.id));
    const matchSanctions = sanctions.filter((sanction) => eventIds.has(sanction.sourceEventId));
    const sanctionIds = new Set(matchSanctions.map((sanction) => sanction.id));
    const involvedEntries = new Set([match.homeEntryId, match.awayEntryId]);
    const matchPlayers = entries
      .filter((entry) => involvedEntries.has(entry.id))
      .flatMap((entry) => (rosterByEntry.get(entry.id) ?? []).slice(0, 10).map((playerId) => ({
        displayName: playerById.get(playerId)!.name,
        entryId: entry.id,
        playerProfileId: playerId,
        side: entry.id === match.homeEntryId ? "HOME" : "AWAY",
        squadStatus: "locked",
      })));
    return [match.id, {
      ...base,
      events: matchEvents,
      filters: { canonicalMatchId: match.canonicalMatchId },
      health: {
        activeSanctions: matchSanctions.filter(({ status }) => ["active", "provisional", "under_review"].includes(status)).length,
        counterRows: counters.length,
        latestServerSequence: authorityProof.operationReceipts.discipline,
        pendingAppeals: 0,
      },
      matchContext: {
        awayEntryId: match.awayEntryId,
        canonicalMatchId: match.canonicalMatchId,
        homeEntryId: match.homeEntryId,
        id: match.contextId,
        scheduledStart: match.scheduledStart,
        status: match.status,
        timezone: "Europe/Madrid",
        venueLabel: match.venueLabel,
      },
      matchPlayers,
      playerStates: playerStates.filter((state) => involvedEntries.has(state.entryId)),
      sanctions: matchSanctions,
      serviceEvents: serviceEvents.filter((service) => sanctionIds.has(service.sanctionId)),
    } satisfies CompetitionDisciplineJson];
  }));
  return { disciplinePreview: base, matchDisciplinePreviews };
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
  const { disciplinePreview, matchDisciplinePreviews } = buildDisciplinePreviews(
    authorityProof,
    entries,
    matches,
    playerById,
    rosterByEntry,
  );
  const refereeAssignments = buildRefereeAssignmentPreviews(authorityProof, matches, teamById);
  return {
    competition: {
      category: { id: id("category"), name: "Senior", sportFormat: "FOOTBALL_7", status: "active" },
      division: { id: id("division"), name: "División única", status: "active" },
      edition: { id: id("edition"), name: "Temporada 2026/27", seasonLabel: DEMO_WORLD_SEASON, status: "completed" },
      group: { id: id("group"), name: "Grupo A", status: "completed" },
      id: id("competition"),
      name: "LIGA BARRIOS IQ 2026/27",
      privateBeta: true,
      refereeAssignmentsEnabled: true,
      ruleRevision: { id: id("rules"), status: "frozen", version: 1 },
      slug: "liga-barrios-iq-2026-27",
      stage: { id: id("stage"), name: "Liga regular", status: "completed", type: "LEAGUE_STAGE" },
      status: "completed",
      visibility: "private",
    },
    delegates: entries.map((entry, index) => ({ entryId: entry.id, id: id("delegate", index + 1), role: "PRIMARY_DELEGATE", status: "active" })),
    disciplinePreview,
    entries,
    matchDisciplinePreviews,
    matchPreviews: Object.fromEntries(matches.map((match) => [match.id, buildMatchPreview(match, teamById, playerById, entryById, rosterByEntry)])),
    matches,
    provenance: {
      authorityHash: authorityProof.authorityHash,
      database: "temporary-local-postgresql",
      migrations: authorityProof.migrationCount,
      oracle: "independent-basic-standings-v1",
      rpcFamilies: ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5"],
      source: "simulation-world",
      verified: true,
    },
    refereeAssignmentDeskPreview: refereeAssignments.desk,
    refereeAssignmentPreviews: refereeAssignments.perMatch,
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

function buildClubsReferees(
  teams: DemoWorldTeam[],
  authorityProof: DemoWorldV2AuthorityProof,
  refereeAssignmentPreview: DemoWorldV2CompetitionChunk["refereeAssignmentDeskPreview"],
): DemoWorldV2ClubsRefereesChunk {
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
  const referees = authorityProof.refereeAssignments.profiles.map((profile) => {
    const refereeId = `demo_referee_${String(profile.refereeNumber).padStart(3, "0")}`;
    return {
    availabilityStatus: profile.availabilityStatus,
    clubIds: clubs.filter(({ refereeIds }) => refereeIds.includes(refereeId)).map(({ id: clubId }) => clubId),
    displayName: profile.displayName,
    id: refereeId,
    marketplaceStatus: "listed" as const,
    modalities: profile.modalities,
    municipality: profile.municipality,
    publicBio: profile.publicBio,
    publicFee: profile.publicFee,
    slug: profile.slug,
    statistics: profile.statistics,
    verificationStatus: profile.verificationStatus,
  }});
  return {
    clubs,
    refereeAssignmentPreview,
    refereeAssignmentsEnabled: true,
    referees,
    relationships: [
      ...clubs.flatMap((club) => club.teamIds.map((teamId, index) => ({ clubId: club.id, id: `${club.id}_team_${index + 1}`, status: "active" as const, teamId, type: "club_team" as const }))),
      ...clubs.flatMap((club) => club.refereeIds.map((refereeId, index) => ({ clubId: club.id, id: `${club.id}_referee_${index + 1}`, refereeId, status: "active" as const, type: "club_referee" as const }))),
    ],
  };
}

function buildConfiguration(
  authorityProof: DemoWorldV2AuthorityProof,
): DemoWorldV2ConfigurationChunk {
  const configuration = authorityProof.configuration;
  return {
    comparator: structuredClone(configuration.comparator),
    competitionName: configuration.competitionName,
    currentEditionRevision: configuration.currentEditionRevision,
    engineConsumption: {
      r5CatalogCodes: structuredClone(configuration.r5CatalogCodes),
      refereePolicy: structuredClone(configuration.refereePolicyConsumed),
    },
    futureCapabilities: {
      automaticRoundRobin: true,
      ...structuredClone(configuration.futureCapabilities),
    },
    health: structuredClone(configuration.health),
    provenance: {
      authorityHash: authorityProof.authorityHash,
      database: authorityProof.database,
      operationReceipts: configuration.operationReceipts,
      source: "simulation-world",
      verified: true,
    },
    readOnly: true,
    revisions: structuredClone(configuration.revisions),
    transport: { methods: ["GET"], remoteWrites: 0 },
  };
}

function buildTournament(
  teams: DemoWorldTeam[],
  authorityProof: DemoWorldV2AuthorityProof,
): DemoWorldV2TournamentChunk {
  const authority = authorityProof.tournament;
  const teamByNumber = new Map(teams.slice(0, 16).map((team, index) => [index + 1, team]));
  const teamRef = (teamNumber: number) => {
    const team = teamByNumber.get(teamNumber);
    if (!team) throw new Error(`DEMO_WORLD_V2_5_TEAM_LINEAGE_INVALID:${teamNumber}`);
    return { id: team.id, name: team.name };
  };
  const authorityTeamRef = (source: { name: string; teamNumber: number }) => {
    const team = teamRef(source.teamNumber);
    if (team.name !== source.name) {
      throw new Error(`DEMO_WORLD_V2_6_TEAM_LINEAGE_INVALID:${source.teamNumber}`);
    }
    return team;
  };
  const drawOutcomes = authority.drawOutcomes.map((outcome): DemoWorldV2TournamentOutcome => ({
    ...structuredClone(outcome),
    locks: outcome.locks.map((lock) => {
      const team = teamByNumber.get(lock.entryNumber);
      if (!team || team.name !== lock.teamName) throw new Error("DEMO_WORLD_V2_4_TEAM_LINEAGE_INVALID");
      return {
        entryNumber: lock.entryNumber,
        groupNumber: lock.groupNumber,
        slotNumber: lock.slotNumber,
        team: { id: team.id, name: team.name },
      };
    }),
    placements: outcome.placements.map((placement) => {
      const team = teamByNumber.get(placement.entryNumber);
      if (!team || team.name !== placement.teamName) throw new Error("DEMO_WORLD_V2_4_TEAM_LINEAGE_INVALID");
      return {
        entryNumber: placement.entryNumber,
        groupNumber: placement.groupNumber,
        placementSource: placement.placementSource,
        potNumber: placement.potNumber,
        slotNumber: placement.slotNumber,
        team: { id: team.id, name: team.name },
      };
    }),
  }));
  const automatic = drawOutcomes[0]!;
  const hybrid = drawOutcomes[1]!;
  const automaticByTeam = new Map(automatic.placements.map((placement) => [placement.team.id, placement]));
  const movedTeams = hybrid.placements.flatMap((placement) => {
    const previous = automaticByTeam.get(placement.team.id);
    if (!previous || previous.groupNumber === placement.groupNumber) return [];
    return [{
      fromGroup: previous.groupNumber,
      team: structuredClone(placement.team),
      toGroup: placement.groupNumber,
    }];
  });
  const groupStage = {
    currentRound: authority.groupStagePublic.currentRound,
    discipline: authority.groupStagePublic.discipline.map((event) => ({
      cardType: event.cardType,
      playerLabel: event.playerLabel,
      status: event.status,
      team: teamRef(event.teamNumber),
    })),
    fixtureCount: authority.groupStagePublic.fixtureCount,
    groupCount: authority.groupStagePublic.groupCount,
    incidents: structuredClone(authority.groupStagePublic.incidents),
    matches: authority.groupStagePublic.matches.map((match) => ({
      awayTeam: teamRef(match.awayTeamNumber),
      disciplineEvents: match.disciplineEvents,
      groupNumber: match.groupNumber,
      homeTeam: teamRef(match.homeTeamNumber),
      incidentType: match.incidentType,
      matchKey: match.matchKey,
      ...(match.refereeNumber === undefined ? {} : { refereeNumber: match.refereeNumber }),
      roundNumber: match.roundNumber,
      scheduledStart: match.scheduledStart,
      ...(match.score === undefined ? {} : { score: structuredClone(match.score) }),
      status: match.status,
      venueLabel: match.venueLabel,
    })),
    officialMatches: authority.groupStagePublic.officialMatches,
    qualificationStatus: authority.groupStagePublic.qualificationStatus,
    referees: structuredClone(authority.groupStagePublic.referees),
    roundCount: authority.groupStagePublic.roundCount,
    sanctions: authority.groupStagePublic.sanctions.map((sanction) => ({
      publicSummary: sanction.publicSummary,
      remainingUnits: sanction.remainingUnits,
      status: sanction.status,
      team: teamRef(sanction.teamNumber),
      unitType: sanction.unitType,
    })),
    scheduledMatches: authority.groupStagePublic.scheduledMatches,
    standings: authority.groupStagePublic.standings.map((standing) => ({
      criteria: structuredClone(standing.criteria ?? []),
      draws: standing.draws,
      goalDifference: standing.goalDifference,
      goalsAgainst: standing.goalsAgainst,
      goalsFor: standing.goalsFor,
      groupNumber: standing.groupNumber,
      losses: standing.losses,
      played: standing.played,
      points: standing.points,
      position: standing.position,
      qualificationZone: standing.qualificationZone ?? false,
      revision: standing.revision ?? 0,
      status: standing.status ?? "PROVISIONAL",
      team: teamRef(standing.teamNumber),
      wins: standing.wins,
    })),
  } satisfies DemoWorldV2TournamentChunk["groupStage"];
  const knockout = {
    authority: {
      activeMatches: authority.knockoutProof.matches.active,
      advanceDecisions: authority.knockoutProof.progression.advanceDecisions,
      completionSnapshots: authority.knockoutProof.completion.snapshots,
      correction: {
        nodeHistoryRetained: authority.knockoutProof.correction.nodeHistoryRetained,
        oldContextRetired: authority.knockoutProof.correction.oldContextRetired,
        oldMatchRetired: authority.knockoutProof.correction.oldMatchRetired,
        replacementCreated: authority.knockoutProof.correction.replacementCreated,
      },
      dependencyImpacts: authority.knockoutProof.progression.dependencyImpacts,
      historicalMatches: authority.knockoutProof.matches.historical,
      integrity: {
        billingUnchanged: authority.knockoutProof.integrity.billingUnchanged,
        conductUnchanged: authority.knockoutProof.integrity.conductUnchanged,
        ratingV2Unchanged: authority.knockoutProof.integrity.ratingV2Unchanged,
        rewardsUnchanged: authority.knockoutProof.integrity.rewardsUnchanged,
      },
      invalidations: authority.knockoutProof.progression.invalidations,
      noShowResolutionLinked: authority.knockoutProof.r4d.knockoutNoShowResolution,
      penaltySeparation: {
        groupStandingsUnchanged: authority.knockoutProof.penaltySeparation.groupStandingsUnchanged,
        shootoutGoalsAddedToSportingScore: authority.knockoutProof.penaltySeparation.shootoutGoalsAddedToSportingScore,
      },
      readModelCanonical: authority.knockoutProof.readModel.serverSequencePresent
        && authority.knockoutProof.readModel.checksumPresent,
      retiredMatches: authority.knockoutProof.matches.retired,
    },
    discipline: {
      blockedFromSemifinal: authority.knockoutPublic.discipline.blockedFromSemifinal,
      playerLabel: authority.knockoutPublic.discipline.playerLabel,
      ratingChanged: authority.knockoutPublic.discipline.ratingChanged,
      sanctionApplies: authority.knockoutPublic.discipline.sanctionApplies,
      team: teamRef(authority.knockoutPublic.discipline.teamNumber),
    },
    format: authority.knockoutPublic.format,
    nodes: authority.knockoutPublic.nodes.map((node) => ({
      awayTeam: authorityTeamRef(node.awayTeam),
      ...(node.extraTime === undefined ? {} : { extraTime: structuredClone(node.extraTime) }),
      homeTeam: authorityTeamRef(node.homeTeam),
      loserTeamId: teamRef(node.loserTeamNumber).id,
      nodeKey: node.nodeKey,
      nodeOrder: node.nodeOrder,
      ...(node.referee === undefined ? {} : { referee: structuredClone(node.referee) }),
      regulationScore: structuredClone(node.regulationScore),
      resolutionKind: node.resolutionKind,
      roundCode: node.roundCode,
      roundOrder: node.roundOrder,
      scheduledStart: node.scheduledStart,
      score: structuredClone(node.score),
      ...(node.shootout === undefined ? {} : { shootout: structuredClone(node.shootout) }),
      status: node.status,
      venueLabel: node.venueLabel,
      winnerTeamId: teamRef(node.winnerTeamNumber).id,
    })),
    organizerDesk: structuredClone(authority.knockoutPublic.organizerDesk),
    podium: {
      champion: authorityTeamRef(authority.knockoutPublic.podium.champion),
      fourthPlace: authorityTeamRef(authority.knockoutPublic.podium.fourthPlace),
      runnerUp: authorityTeamRef(authority.knockoutPublic.podium.runnerUp),
      thirdPlace: authorityTeamRef(authority.knockoutPublic.podium.thirdPlace),
    },
    referees: structuredClone(authority.knockoutProof.referees),
    rounds: structuredClone(authority.knockoutPublic.rounds),
    status: authority.knockoutPublic.status,
    teamJourneys: authority.knockoutPublic.teamJourneys.map((journey) => ({
      finalPosition: journey.finalPosition,
      path: structuredClone(journey.path),
      status: journey.status,
      team: authorityTeamRef({ name: journey.teamName, teamNumber: journey.teamNumber }),
    })),
    thirdPlaceEnabled: authority.knockoutPublic.thirdPlaceEnabled,
  } satisfies DemoWorldV2TournamentChunk["knockout"];
  return {
    comparison: {
      movedTeams,
      qualityDelta: Number((hybrid.qualityScore - automatic.qualityScore).toFixed(3)),
      retainedLocks: hybrid.locks.length,
    },
    competition: {
      acceptedParticipants: authority.acceptedParticipants,
      groupCount: authority.groupCount,
      name: authority.competitionName,
      planStatus: authority.planStatus,
      potCount: authority.potCount,
      publishedRevision: authority.publishedRevision,
      slug: authority.slug,
    },
    conflict: {
      ...structuredClone(authority.conflict),
      explanation: "Dos equipos fueron fijados en la misma posición. El motor rechazó el sorteo y propuso liberar un lock o suavizar una restricción HARD.",
    },
    constraints: structuredClone(authority.constraints),
    completionProof: {
      bracketSize: authority.groupStageFinal.bracketSize,
      bracketSources: authority.groupStageFinal.bracketSlots.map((slot) => ({
        matchNumber: slot.matchNumber,
        side: slot.side,
        slotKey: slot.slotKey,
        sourceGroupNumber: slot.sourceGroupNumber,
        sourceKind: slot.sourceKind,
        sourcePosition: slot.sourcePosition,
        status: slot.status,
      })),
      bracketStatus: authority.groupStageFinal.bracketStatus,
      canonicalMatches: authority.groupStageFinal.canonicalMatches,
      eliminated: authority.groupStageFinal.eliminated,
      knockoutMatches: authority.groupStageFinal.knockoutMatches,
      officialMatches: authority.groupStageFinal.officialMatches,
      progressionEnabled: authority.groupStageFinal.bracketProgressionEnabled,
      qualificationChecksum: authority.groupStageFinal.qualificationChecksum,
      qualificationStatus: authority.groupStageFinal.qualificationStatus,
      qualifiers: authority.groupStageFinal.qualifiers,
      standingSnapshots: authority.groupStageFinal.standingSnapshots,
    },
    drawOutcomes: drawOutcomes as [DemoWorldV2TournamentOutcome, DemoWorldV2TournamentOutcome],
    groupStage,
    knockout,
    nextPhase: {
      bracketProgression: true,
      knockoutMatches: authority.knockoutProof.matches.active,
      message: "Torneo completado y cuadro bloqueado por PostgreSQL.",
      tournamentMatches: authority.tournamentMatches + authority.knockoutProof.matches.active,
    },
    provenance: {
      authorityHash: authorityProof.authorityHash,
      database: authorityProof.database,
      operationReceipts: authority.operationReceipts,
      rpcFamilies: ["R1", "CONFIGURATION_CENTER", "ENTRIES", "R4B", "R4C", "R4D", "R5", "REFEREES", "R6A_DRAW_ENGINE", "R6B_GROUP_STAGE", "R6C_KNOCKOUT"],
      source: "simulation-world",
      verified: true,
    },
    readOnly: true,
    transport: { methods: ["GET"], remoteWrites: 0 },
  };
}

export function generateDemoWorldV2(
  authorityProof = loadDemoWorldV2AuthorityProof(),
): DemoWorldV2Snapshot {
  const v1 = generateDemoWorld();
  const competitions = buildCompetition(v1.core.teams, v1.players.players, authorityProof);
  const clubsReferees = buildClubsReferees(
    v1.core.teams,
    authorityProof,
    competitions.refereeAssignmentDeskPreview,
  );
  const configuration = buildConfiguration(authorityProof);
  const tournament = buildTournament(v1.core.teams, authorityProof);
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
  const payload = { activity, clubsReferees, competitions, configuration, core, matches, players, tournament };
  const snapshotHash = hash(payload);
  const cacheKey = snapshotHash.slice(0, 16);
  const manifest: DemoWorldV2Manifest = {
    chunks: {
      activity: `/demo-world/v2/activity.json?h=${cacheKey}`,
      clubsReferees: `/demo-world/v2/clubs-referees.json?h=${cacheKey}`,
      competitions: `/demo-world/v2/competitions.json?h=${cacheKey}`,
      configuration: `/demo-world/v2/configuration.json?h=${cacheKey}`,
      core: `/demo-world/v2/core.json?h=${cacheKey}`,
      matches: `/demo-world/v2/matches.json?h=${cacheKey}`,
      players: `/demo-world/v2/players.json?h=${cacheKey}`,
      tournament: `/demo-world/v2/tournament.json?h=${cacheKey}`,
    },
    counts: {
      achievements: activity.achievements.length,
      canonicalMatches: competitions.matches.length
        + tournament.groupStage.matches.length
        + tournament.knockout.nodes.length
        + tournament.knockout.authority.retiredMatches,
      challenges: matches.challenges.length,
      clubs: clubsReferees.clubs.length,
      competitions: 1,
      matches: matches.matches.length,
      notifications: activity.notifications.length,
      players: players.players.length,
      referees: clubsReferees.referees.length,
      ruleRevisions: configuration.revisions.length,
      rewardBoxes: activity.rewardBoxes.length,
      rounds: competitions.rounds.length
        + tournament.groupStage.roundCount
        + tournament.knockout.rounds.length,
      stories: core.stories.length,
      teams: core.teams.length,
      tournamentDrawRevisions: authorityProof.tournament.totalRevisions,
      tournamentGroups: tournament.competition.groupCount,
      tournaments: 1,
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
    "configuration.json": snapshot.configuration,
    "core.json": snapshot.core,
    "manifest.json": snapshot.manifest,
    "matches.json": snapshot.matches,
    "players.json": snapshot.players,
    "tournament.json": snapshot.tournament,
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
    configuration: snapshot.configuration,
    core: snapshot.core,
    matches: snapshot.matches,
    players: snapshot.players,
    tournament: snapshot.tournament,
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
