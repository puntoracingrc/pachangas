import type { LeagueOperationalJson } from "../league-operational-exceptions-contract";

const competitionId = "d4d00000-0000-4000-8000-000000000001";
const matchId = "d4d00000-0000-4000-8000-000000000002";
const contextId = "d4d00000-0000-4000-8000-000000000003";
const homeEntryId = "d4d00000-0000-4000-8000-000000000004";
const awayEntryId = "d4d00000-0000-4000-8000-000000000005";

const flags = {
  administrativeDecisionsEnabled: true,
  foundationEnabled: true,
  lateArrivalEnabled: true,
  matchSuspensionsEnabled: true,
  noShowEnabled: true,
  postponementsEnabled: true,
  publicExceptionStatusEnabled: true,
  reschedulingEnabled: true,
  revision: 18,
  serverSequence: 9042,
  venueChangesEnabled: true,
};

const request = {
  competitionId,
  contextId,
  id: "d4d00000-0000-4000-8000-000000000010",
  canonicalMatchId: matchId,
  proposedEnd: "2026-09-19T21:30:00.000Z",
  proposedStart: "2026-09-19T20:00:00.000Z",
  proposedTimezone: "Europe/Madrid",
  publicSummary: "Cambio solicitado por indisponibilidad del campo original.",
  reasonCode: "PITCH_UNAVAILABLE",
  requestingEntry: { id: homeEntryId, name: "Cobalto Reial" },
  requestingEntryId: homeEntryId,
  respondingEntry: { id: awayEntryId, name: "Vértice Gràcia" },
  respondingEntryId: awayEntryId,
  responseDeadline: "2026-09-15T20:00:00.000Z",
  revision: 2,
  serverSequence: 9033,
  status: "awaiting_response",
  teamResponse: "PENDING",
};

const suspension = {
  canonicalMatchId: matchId,
  id: "d4d00000-0000-4000-8000-000000000012",
  publicSummary: "Iluminación insuficiente.",
  reasonCode: "LIGHTING",
  reportedMinute: 37,
  revision: 2,
  serverSequence: 9038,
  sportingScoreAway: 0,
  sportingScoreHome: 1,
  status: "confirmed",
};

const decision = {
  decidedAt: "2026-09-14T22:04:00.000Z",
  decisionType: "RESCHEDULE_MATCH",
  id: "d4d00000-0000-4000-8000-000000000013",
  publicSummary: "Nueva fecha validada por competición.",
  reasonCode: "BILATERAL_APPROVAL",
  revision: 1,
  serverSequence: 9039,
  status: "published",
};

export const leagueOperationalFixtures: Record<string, LeagueOperationalJson> = {
  match: {
    administrativeDecisions: [decision],
    context: {
      awayEntryId,
      canonicalMatchId: matchId,
      competitionId,
      homeEntryId,
      id: contextId,
      revision: 7,
      scheduledEnd: "2026-09-19T21:30:00.000Z",
      scheduledStart: "2026-09-19T20:00:00.000Z",
      serverSequence: 9042,
      status: "postponed",
      timezone: "Europe/Madrid",
      venueLabel: "Pista Municipal Llevant",
      venueStatus: "LABEL",
    },
    effectiveFixtureChange: {
      changeType: "RESCHEDULE",
      publicSummary: "Nueva fecha validada por competición.",
      revision: 1,
      serverSequence: 9039,
      status: "active",
    },
    flags,
    kind: "LeagueOperationalMatchView",
    lateArrivalIncidents: [{ graceDeadline: "2026-09-19T20:12:00.000Z", id: "d4d00000-0000-4000-8000-000000000011", responsibleEntryId: awayEntryId, serverSequence: 9035, status: "reported" }],
    noShowIncidents: [],
    originalSchedule: { revision: 1, scheduledEnd: "2026-09-12T21:30:00.000Z", scheduledStart: "2026-09-12T20:00:00.000Z", timezone: "Europe/Madrid", venueLabel: "Camp Nord" },
    permissions: { actorCompetitionRole: "competition_operations_manager", manageAway: false, manageHome: true, manageOperations: true },
    postponementRequests: [request],
    revision: 7,
    serverSequence: 9042,
    suspensions: [suspension],
    venueChangeRequests: [],
  },
  postponements: { competitionId, counts: { expiredDeadlines: 1, pending: 2, postponedMatches: 1 }, flags, items: [request], kind: "LeaguePostponementDesk" },
  incidents: { competitionId, counts: { lateArrivalOpen: 1, noShowPending: 1, suspended: 1 }, flags, kind: "LeagueIncidentDesk", lateArrivals: [{ ...leagueOperationalRecordForDemo(request), id: "d4d00000-0000-4000-8000-000000000011", canonicalMatchId: matchId, graceDeadline: "2026-09-19T20:12:00.000Z", responsibleEntry: { id: awayEntryId, name: "Vértice Gràcia" }, status: "reported" }], noShows: [{ canonicalMatchId: matchId, id: "d4d00000-0000-4000-8000-000000000014", publicSummary: "Incidencia pendiente de revisión.", reasonCode: "GRACE_EXPIRED", responsibleEntry: { id: awayEntryId, name: "Vértice Gràcia" }, revision: 1, serverSequence: 9040, status: "under_review" }], suspensions: [suspension] },
  decisions: { competitionId, flags, items: [{ ...decision, effects: [{ id: "d4d00000-0000-4000-8000-000000000015", serverSequence: 9039, status: "applied", type: "RESCHEDULE_MATCH" }] }], kind: "LeagueAdministrativeDecisionDesk" },
  my: { flags, items: [{ ...request, actorScope: "REQUESTING_TEAM", responses: [] }], kind: "MyLeagueExceptionRequests" },
  public: { canonicalMatchId: matchId, competitionId, effectiveSchedule: { scheduledStart: "2026-09-19T20:00:00.000Z", timezone: "Europe/Madrid", venueLabel: "Pista Municipal Llevant" }, kind: "PublicLeagueFixtureStatus", latestChange: { effectiveAt: "2026-09-14T22:04:00.000Z", reasonCode: "BILATERAL_APPROVAL", revision: 1, serverSequence: 9039, summary: "Nueva fecha validada por competición.", type: "RESCHEDULE" }, originalSchedule: { scheduledStart: "2026-09-12T20:00:00.000Z", timezone: "Europe/Madrid", venueLabel: "Camp Nord" }, revision: 7, serverSequence: 9042, status: "postponed", statusLabel: "Aplazado" },
};

function leagueOperationalRecordForDemo(value: LeagueOperationalJson) {
  return { revision: value.revision, serverSequence: value.serverSequence };
}
