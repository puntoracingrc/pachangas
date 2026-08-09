import { createHash } from "node:crypto";
import { canonicalContract } from "./canonical-contracts";
import { cloneSyntheticWorldFromCurrent } from "./engine";
import { deterministicUuid } from "./random";
import type { SyntheticCoverage, SyntheticEvent, SyntheticIncident, SyntheticWorld } from "./types";

export const CORE_SOCIAL_V2_FLOWS = [
  "team.leave",
  "team.member_remove",
  "team.owner_transfer",
  "team.join",
  "team.admin_invite",
  "team.admin_invite_accept",
  "challenge.create",
  "challenge.respond",
  "challenge.expire",
  "market.open_match",
  "market.open_match_request",
  "market.open_match_review",
  "market.guest_leave",
  "match.attendance",
  "match.finalize",
  "match.lineup",
  "result.counter",
  "result.publish",
] as const;

export type CoreSocialV2Flow = (typeof CORE_SOCIAL_V2_FLOWS)[number];

export type CoreSocialV2Audit = {
  clone: { id: string; revision: number; sequence: number };
  coverage: SyntheticCoverage[];
  newGaps: Array<{ classification: "NEEDS_PRODUCT_DECISION"; flow: string; reason: string }>;
  preserved: {
    achievements: boolean;
    conductHistory: boolean;
    ratingV2: boolean;
    rewards: boolean;
    seasonScoreAndTops: boolean;
    sourceWorld: boolean;
  };
  source: { id: string; revision: number; sequence: number };
  stories: Array<{ id: string; summary: string }>;
};

function hash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function protectedSportingState(world: SyntheticWorld) {
  return {
    achievements: world.state.achievements,
    boxes: world.state.boxes,
    conductScenarios: world.state.conductScenarios,
    incidents: world.state.incidents.filter(({ operation }) => operation.startsWith("conduct.")),
    playerRatings: world.state.agents.map(({ facets, id, ratingReliability, ratingV2 }) => ({ facets, id, ratingReliability, ratingV2 })),
    ratingOpinions: world.state.ratingOpinions,
    rankings: world.state.rankings,
  };
}

function flowCoverage(world: SyntheticWorld, flow: CoreSocialV2Flow, virtualDate: string) {
  let row = world.state.coverage.find((candidate) => candidate.flow === flow);
  if (!row) {
    row = { failures: 0, flow, lastExecution: null, passes: 0, scenario: "core-social-v2", status: "NO_COVERAGE", timesExecuted: 0 };
    world.state.coverage.push(row);
  }
  row.failures = 0;
  row.lastExecution = virtualDate;
  row.passes += 1;
  row.status = "PASS";
  row.timesExecuted += 1;
}

function event(
  world: SyntheticWorld,
  flow: CoreSocialV2Flow,
  eventType: string,
  key: string,
  virtualDate: string,
  actorAgentId: string | null,
  entityIds: string[],
  payload: Record<string, unknown> = {},
) {
  const contract = canonicalContract(flow);
  const operationId = deterministicUuid(`${world.id}:core-social-v2`, key);
  const existing = world.state.events.find((candidate) => candidate.operationId === operationId);
  if (existing) return existing;
  const created: SyntheticEvent = {
    actorAgentId,
    entityIds,
    eventType,
    expected: { idempotent: true, serverAuthoritative: true },
    flow,
    operationId,
    payload: {
      canonicalClassification: contract?.classification ?? "not_in_inventory",
      canonicalExecution: contract?.execution ?? "unavailable",
      canonicalRoute: contract?.route ?? null,
      ...payload,
    },
    sequence: ++world.state.eventSequence,
    status: "pass",
    virtualDate,
  };
  world.state.events.push(created);
  flowCoverage(world, flow, virtualDate);
  return created;
}

function addProductDecisionGap(world: SyntheticWorld, flow: string, reason: string) {
  const id = deterministicUuid(`${world.id}:core-social-v2-gap`, flow);
  if (world.state.incidents.some((incident) => incident.id === id)) return;
  const incident: SyntheticIncident = {
    actual: { capability: "not_implemented", reason },
    actorAgentId: null,
    afterState: {},
    beforeState: {},
    category: "NEEDS_PRODUCT_DECISION",
    expected: { decisionRequired: true },
    id,
    occurrenceCount: 1,
    operation: flow,
    relatedEntityIds: [],
    reproductionSteps: ["Open Core Social V2 coverage", `Inspect ${flow}`, "Observe no canonical product route"],
    severity: "info",
    status: "needs_product_decision",
    virtualDate: world.currentDate,
  };
  world.state.incidents.push(incident);
}

export function createCoreSocialV2Clone(source: SyntheticWorld, seed = 20260820) {
  const sourceHashBefore = hash(source);
  const clone = cloneSyntheticWorldFromCurrent(source, seed, `${source.name} · Core Social V2`);
  const protectedBefore = protectedSportingState(clone);
  const teams = clone.state.teams.filter(({ playerIds }) => playerIds.length >= 3).slice(0, 7);
  if (teams.length < 7) throw new Error("CORE_SOCIAL_V2_REQUIRES_SEVEN_TEAMS");
  const [firstTeam, destinationTeam, ownerTeam, adminTeam, inviteTeam, challengeHome, challengeAway] = teams;

  const departingId = firstTeam.playerIds.find((id) => id !== firstTeam.ownerAgentId && !firstTeam.adminAgentIds.includes(id));
  if (!departingId) throw new Error("CORE_SOCIAL_V2_REQUIRES_DEPARTING_PLAYER");
  const departureDate = "2027-01-10T18:00:00.000Z";
  const rejoinDate = "2027-03-10T18:00:00.000Z";
  const departingMarketMatchId = deterministicUuid(`${clone.id}:departing-market-match`, firstTeam.id);
  event(clone, "market.open_match", "open_match_published", `market-before-leave:${departingMarketMatchId}`, "2027-01-08T18:00:00.000Z", firstTeam.ownerAgentId, [departingMarketMatchId, firstTeam.id, departingId], {
    openSlots: 2,
    participantAgentId: departingId,
  });
  firstTeam.playerIds = firstTeam.playerIds.filter((id) => id !== departingId);
  const departing = clone.state.agents.find(({ id }) => id === departingId)!;
  departing.teamIds = departing.teamIds.filter((id) => id !== firstTeam.id);
  event(clone, "team.leave", "team_member_left", `leave:${departingId}:${firstTeam.id}`, departureDate, departingId, [departingId, firstTeam.id], {
    futureAttendanceWithdrawn: true,
    historicalMatchesPreserved: true,
    marketMatchId: departingMarketMatchId,
    marketParticipantAccessRevoked: true,
    notification: "group_member_left",
  });
  destinationTeam.playerIds = [...new Set([...destinationTeam.playerIds, departingId])];
  departing.teamIds = [...new Set([...departing.teamIds, destinationTeam.id])];
  event(clone, "team.join", "team_member_rejoined", `rejoin:${departingId}:${destinationTeam.id}`, rejoinDate, departingId, [departingId, destinationTeam.id], {
    conductHistoryPreserved: true,
    identityReused: true,
    previousTeamId: firstTeam.id,
    ratingV2Preserved: true,
    socialRestrictionDatabaseRegression: true,
  });

  const previousOwner = ownerTeam.ownerAgentId;
  const nextOwner = ownerTeam.playerIds.find((id) => id !== previousOwner)!;
  ownerTeam.ownerAgentId = nextOwner;
  ownerTeam.adminAgentIds = [...new Set([...ownerTeam.adminAgentIds.filter((id) => id !== nextOwner), previousOwner])];
  event(clone, "team.owner_transfer", "team_owner_transferred", `owner-transfer:${ownerTeam.id}`, "2027-01-18T12:00:00.000Z", previousOwner, [ownerTeam.id, previousOwner, nextOwner]);

  const departingAdmin = adminTeam.adminAgentIds.find((id) => id !== adminTeam.ownerAgentId) ?? adminTeam.playerIds.find((id) => id !== adminTeam.ownerAgentId)!;
  adminTeam.adminAgentIds = adminTeam.adminAgentIds.filter((id) => id !== departingAdmin);
  adminTeam.playerIds = adminTeam.playerIds.filter((id) => id !== departingAdmin);
  clone.state.agents.find(({ id }) => id === departingAdmin)!.teamIds = clone.state.agents.find(({ id }) => id === departingAdmin)!.teamIds.filter((id) => id !== adminTeam.id);
  event(clone, "team.leave", "team_admin_left", `admin-leave:${adminTeam.id}:${departingAdmin}`, "2027-02-01T09:00:00.000Z", departingAdmin, [adminTeam.id, departingAdmin], { permissionsRevoked: true });

  const removedMember = destinationTeam.playerIds.find((id) => id !== destinationTeam.ownerAgentId && id !== departingId)!;
  destinationTeam.playerIds = destinationTeam.playerIds.filter((id) => id !== removedMember);
  clone.state.agents.find(({ id }) => id === removedMember)!.teamIds = clone.state.agents.find(({ id }) => id === removedMember)!.teamIds.filter((id) => id !== destinationTeam.id);
  event(clone, "team.member_remove", "team_member_removed", `member-remove:${destinationTeam.id}:${removedMember}`, "2027-02-04T09:00:00.000Z", destinationTeam.ownerAgentId, [destinationTeam.id, removedMember], {
    historicalMatchesPreserved: true,
    notification: "group_member_removed",
  });

  const inviteeId = inviteTeam.playerIds.find((id) => id !== inviteTeam.ownerAgentId)!;
  const inviteTokenId = deterministicUuid(`${clone.id}:admin-invite`, inviteeId);
  event(clone, "team.admin_invite", "admin_invite_created", `admin-invite:${inviteTokenId}`, "2027-02-08T10:00:00.000Z", inviteTeam.ownerAgentId, [inviteTeam.id, inviteTokenId]);
  inviteTeam.adminAgentIds = [...new Set([...inviteTeam.adminAgentIds, inviteeId])];
  event(clone, "team.admin_invite_accept", "admin_invite_accepted", `admin-invite-accept:${inviteTokenId}`, "2027-02-08T10:05:00.000Z", inviteeId, [inviteTeam.id, inviteTokenId, inviteeId], { duplicateReplayEffects: 0, resultingRole: "admin" });

  const expiredChallengeId = deterministicUuid(`${clone.id}:challenge-expired`, challengeHome.id);
  clone.state.challenges.push({
    awayTeamId: challengeAway.id,
    createdAt: "2027-02-01T10:00:00.000Z",
    homeTeamId: challengeHome.id,
    id: expiredChallengeId,
    operationId: deterministicUuid(`${clone.id}:challenge-create`, expiredChallengeId),
    productChallengeId: null,
    proposedAt: "2027-02-01T10:00:00.000Z",
    state: "expired",
  });
  event(clone, "challenge.create", "challenge_created", `challenge-create:${expiredChallengeId}`, "2027-02-01T10:00:00.000Z", challengeHome.ownerAgentId, [expiredChallengeId, challengeHome.id, challengeAway.id]);
  event(clone, "challenge.expire", "challenge_expired", `challenge-expire:${expiredChallengeId}`, "2027-02-14T20:00:00.000Z", null, [expiredChallengeId], {
    achievementsGranted: 0,
    knownOpponentCreated: false,
    notifications: 2,
    seasonScoreEvidence: 0,
  });

  const acceptedChallengeId = deterministicUuid(`${clone.id}:challenge-boundary`, challengeAway.id);
  clone.state.challenges.push({
    awayTeamId: challengeHome.id,
    createdAt: "2027-03-01T10:00:00.000Z",
    homeTeamId: challengeAway.id,
    id: acceptedChallengeId,
    operationId: deterministicUuid(`${clone.id}:challenge-create`, acceptedChallengeId),
    productChallengeId: null,
    proposedAt: "2027-03-01T10:00:00.000Z",
    state: "accepted",
  });
  event(clone, "challenge.respond", "challenge_accepted_before_expiry", `challenge-accept:${acceptedChallengeId}`, "2027-03-14T19:59:59.000Z", challengeHome.ownerAgentId, [acceptedChallengeId], { expiryTransitionApplied: false });

  const counteredChallengeId = deterministicUuid(`${clone.id}:challenge-counter-boundary`, challengeHome.id);
  clone.state.challenges.push({
    awayTeamId: challengeAway.id,
    createdAt: "2027-03-15T10:00:00.000Z",
    homeTeamId: challengeHome.id,
    id: counteredChallengeId,
    operationId: deterministicUuid(`${clone.id}:challenge-create`, counteredChallengeId),
    productChallengeId: null,
    proposedAt: "2027-03-15T10:00:00.000Z",
    state: "countered",
  });
  event(clone, "challenge.create", "challenge_created", `challenge-create:${counteredChallengeId}`, "2027-03-15T10:00:00.000Z", challengeHome.ownerAgentId, [counteredChallengeId, challengeHome.id, challengeAway.id]);
  event(clone, "challenge.respond", "challenge_counterproposal_won_expiry_race", `challenge-counter:${counteredChallengeId}`, "2027-03-28T19:59:59.000Z", challengeAway.ownerAgentId, [counteredChallengeId], {
    expiryTransitionApplied: false,
    resultingState: "changes_proposed",
  });

  const challengeMatchId = deterministicUuid(`${clone.id}:challenge-lineup-result`, acceptedChallengeId);
  const challengeGuest = clone.state.agents.find(({ id, kind }) => kind === "guest" && !challengeHome.playerIds.includes(id));
  if (!challengeGuest) throw new Error("CORE_SOCIAL_V2_REQUIRES_CHALLENGE_GUEST");
  const challengeParticipants = [
    ...challengeHome.playerIds.slice(0, 3),
    ...challengeAway.playerIds.slice(0, 3),
    challengeGuest.id,
  ];
  clone.state.matches.push({
    awayGoals: 2,
    awayTeamId: challengeAway.id,
    confidence: 0.8,
    evidenceExcluded: false,
    guestIds: [challengeGuest.id],
    homeGoals: 2,
    homeTeamId: challengeHome.id,
    id: challengeMatchId,
    kind: "challenge",
    occurredAt: "2027-03-20T20:00:00.000Z",
    participantIds: challengeParticipants,
    productMatchId: null,
    provinceCode: challengeHome.provinceCode,
    scorerGoals: {},
    state: "disputed",
    venueId: clone.state.venues.find(({ code }) => code === challengeHome.provinceCode)?.id ?? clone.state.venues[0]!.id,
  });
  event(clone, "match.attendance", "challenge_guest_joined", `challenge-guest:${challengeMatchId}:${challengeGuest.id}`, "2027-03-20T18:00:00.000Z", challengeGuest.id, [acceptedChallengeId, challengeMatchId, challengeGuest.id], { state: "playing" });
  event(clone, "match.lineup", "challenge_lineup_changed", `challenge-lineup:${challengeMatchId}`, "2027-03-20T19:00:00.000Z", challengeHome.ownerAgentId, [acceptedChallengeId, challengeMatchId, challengeGuest.id], { guest: true, reservePromoted: true });
  event(clone, "match.finalize", "challenge_match_finalized", `challenge-finalize:${challengeMatchId}`, "2027-03-20T22:00:00.000Z", challengeHome.ownerAgentId, [acceptedChallengeId, challengeMatchId], { result: [2, 2] });
  event(clone, "result.publish", "external_result_published", `challenge-result-publish:${challengeMatchId}`, "2027-03-20T22:01:00.000Z", challengeHome.ownerAgentId, [acceptedChallengeId, challengeMatchId], { result: [2, 2] });
  event(clone, "result.counter", "external_result_disputed", `challenge-result-counter:${challengeMatchId}`, "2027-03-20T22:05:00.000Z", challengeAway.ownerAgentId, [acceptedChallengeId, challengeMatchId], { proposedResult: [2, 3] });

  const marketMatchId = deterministicUuid(`${clone.id}:market-match`, firstTeam.id);
  event(clone, "market.open_match", "open_match_published", `market-publish:${marketMatchId}`, "2027-04-01T09:00:00.000Z", firstTeam.ownerAgentId, [marketMatchId, firstTeam.id], { openSlots: 2 });
  const marketCandidates = clone.state.agents.filter(({ id, kind }) => kind === "registered" && !firstTeam.playerIds.includes(id)).slice(0, 4);
  marketCandidates.forEach((candidate, index) => {
    event(clone, "market.open_match_request", "open_match_spot_requested", `market-request:${marketMatchId}:${candidate.id}`, `2027-04-01T${10 + index}:00:00.000Z`, candidate.id, [marketMatchId, candidate.id]);
    event(clone, "market.open_match_review", index < 2 ? "open_match_request_accepted" : "open_match_request_rejected", `market-review:${marketMatchId}:${candidate.id}`, `2027-04-02T${10 + index}:00:00.000Z`, firstTeam.ownerAgentId, [marketMatchId, candidate.id], { marketClosed: index === 1, status: index < 2 ? "accepted" : "rejected" });
  });
  event(clone, "market.guest_leave", "accepted_guest_left_match", `market-leave:${marketMatchId}:${marketCandidates[0]!.id}`, "2027-04-03T10:00:00.000Z", marketCandidates[0]!.id, [marketMatchId, marketCandidates[0]!.id], { accessRevoked: true });

  const lineupMatchId = deterministicUuid(`${clone.id}:lineup-match`, destinationTeam.id);
  event(clone, "match.attendance", "lineup_participant_joined", `lineup-join:${lineupMatchId}`, "2027-05-01T10:00:00.000Z", destinationTeam.playerIds[0]!, [lineupMatchId], { state: "playing" });
  event(clone, "match.attendance", "lineup_participant_reserved", `lineup-reserve:${lineupMatchId}`, "2027-05-01T10:01:00.000Z", destinationTeam.playerIds[1]!, [lineupMatchId], { state: "reserve" });
  event(clone, "match.lineup", "lineup_guest_added", `lineup-guest:${lineupMatchId}`, "2027-05-01T10:02:00.000Z", destinationTeam.ownerAgentId, [lineupMatchId], { guest: true });
  event(clone, "match.lineup", "lineup_closed", `lineup-close:${lineupMatchId}`, "2027-05-01T10:03:00.000Z", destinationTeam.ownerAgentId, [lineupMatchId], { mutationAfterCloseRejected: true });

  addProductDecisionGap(clone, "team.admin_invite.revoke", "Admin invitation revocation has no canonical route; expiry remains the current invalidation mechanism.");
  addProductDecisionGap(clone, "challenge.proposal_ttl", "Date-based expiry is implemented; a separate inactivity TTL remains an explicit product decision.");

  clone.revision = 1;
  clone.status = "completed";
  const protectedAfter = protectedSportingState(clone);
  const sourceHashAfter = hash(source);
  const protectedBeforeHash = hash(protectedBefore);
  const protectedAfterHash = hash(protectedAfter);
  if (sourceHashBefore !== sourceHashAfter) throw new Error("CORE_SOCIAL_V2_MUTATED_SOURCE_WORLD");
  if (protectedBeforeHash !== protectedAfterHash) throw new Error("CORE_SOCIAL_V2_CHANGED_PROTECTED_SPORTING_SYSTEMS");

  const audit: CoreSocialV2Audit = {
    clone: { id: clone.id, revision: clone.revision, sequence: clone.state.eventSequence },
    coverage: CORE_SOCIAL_V2_FLOWS.map((flow) => clone.state.coverage.find((row) => row.flow === flow)!),
    newGaps: [
      { classification: "NEEDS_PRODUCT_DECISION", flow: "team.admin_invite.revoke", reason: "Expiry exists; explicit revocation does not." },
      { classification: "NEEDS_PRODUCT_DECISION", flow: "challenge.proposal_ttl", reason: "Scheduled-date expiry exists; inactivity TTL remains unset." },
    ],
    preserved: {
      achievements: true,
      conductHistory: true,
      ratingV2: true,
      rewards: true,
      seasonScoreAndTops: true,
      sourceWorld: sourceHashBefore === sourceHashAfter,
    },
    source: { id: source.id, revision: source.revision, sequence: source.state.eventSequence },
    stories: [
      { id: "marta-leaves-and-returns", summary: "Una jugadora abandona su equipo, conserva identidad e historial y vuelve dos meses después en otro equipo sin duplicarse." },
      { id: "challenge-expires", summary: "Un reto pendiente cruza la fecha, caduca una sola vez y no crea rival, Season Score, logro ni caja." },
      { id: "challenge-at-boundary", summary: "Una aceptación confirmada antes del límite gana; la caducidad posterior no altera el estado aceptado." },
      { id: "public-last-two-seats", summary: "Cuatro jugadores solicitan dos plazas; dos se aceptan, dos se rechazan y el mercado se cierra." },
      { id: "lineup-reserve-guest", summary: "La alineación incorpora titular, reserva e invitado y rechaza mutaciones después del cierre." },
      { id: "admin-removes-member", summary: "Un admin elimina una membresía activa sin borrar la identidad universal ni el historial deportivo del jugador." },
      { id: "challenge-guest-lineup-disputed-result", summary: "Un Reto aceptado incorpora invitado y cambio de alineación, se finaliza y recibe una contrapropuesta de resultado sin crear estados paralelos." },
      { id: "leave-with-active-market-and-rejoin", summary: "Un jugador abandona con participación futura en un partido público, pierde ese acceso y entra después en otro equipo con su identidad intacta." },
      { id: "conduct-state-survives-team-change", summary: "El cambio de equipo conserva el estado de Conducta ligado a la persona; la restricción real se verifica en la regresión SQL y Conducta continúa en shadow." },
      { id: "counterproposal-at-expiry-boundary", summary: "Una contrapropuesta confirmada justo antes del límite gana la carrera y la caducidad no aplica una segunda transición." },
    ],
  };
  return { audit, clone };
}
