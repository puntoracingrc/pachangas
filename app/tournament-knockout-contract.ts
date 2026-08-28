import {
  tournamentNumber,
  tournamentRecord,
  tournamentText,
  type TournamentJson,
} from "./tournament-draw-contract";

export const tournamentKnockoutActions = [
  "bracket.activate",
  "bracket.reserve_slot",
  "bracket.node.resolve",
  "bracket.node.generate_match",
  "bracket.node.invalidate",
  "bracket.result.advance",
  "bracket.result.recompute",
  "bracket.admin.replace_downstream",
  "bracket.complete_round",
  "bracket.lock_round",
  "tournament.completion.rebuild",
  "tournament.complete",
  "tournament.lock",
] as const;

export type TournamentKnockoutAction = typeof tournamentKnockoutActions[number];

export const tournamentKnockoutReadCacheVersion = 1 as const;
export const tournamentKnockoutRealtimeTable = "pachanga_tournament_invalidations" as const;

export function isTournamentKnockoutAction(value: unknown): value is TournamentKnockoutAction {
  return typeof value === "string"
    && (tournamentKnockoutActions as readonly string[]).includes(value);
}

export function tournamentKnockoutRevision(snapshot: TournamentJson) {
  const bracket = tournamentRecord(snapshot.bracket);
  if (tournamentText(snapshot.kind) === "TournamentBracketView") {
    return tournamentNumber(bracket.revision);
  }
  const knockout = tournamentRecord(snapshot.knockout);
  const activeBracket = tournamentRecord(knockout.bracket);
  return tournamentNumber(
    activeBracket.revision,
    tournamentNumber(tournamentRecord(snapshot.groupStage).revision),
  );
}

export function tournamentKnockoutCacheOrder(snapshot: TournamentJson) {
  const readModel = tournamentRecord(snapshot.readModel);
  const cache = tournamentRecord(snapshot.cache);
  return {
    entityId: tournamentText(cache.entityId, tournamentText(tournamentRecord(snapshot.bracket).id)),
    revision: tournamentNumber(readModel.revision, tournamentNumber(cache.revision)),
    serverSequence: tournamentNumber(readModel.serverSequence, tournamentNumber(cache.serverSequence)),
    updatedAt: tournamentText(readModel.rebuiltAt, tournamentText(cache.updatedAt)),
  };
}

export function compareTournamentKnockoutSnapshots(left: TournamentJson, right: TournamentJson) {
  const a = tournamentKnockoutCacheOrder(left);
  const b = tournamentKnockoutCacheOrder(right);
  if (a.serverSequence !== b.serverSequence) return a.serverSequence - b.serverSequence;
  if (a.revision !== b.revision) return a.revision - b.revision;
  if (a.updatedAt !== b.updatedAt) return a.updatedAt.localeCompare(b.updatedAt);
  return a.entityId.localeCompare(b.entityId);
}

export function tournamentKnockoutTopology(
  bracketSize: number,
  participantCount = bracketSize,
  thirdPlaceEnabled = false,
) {
  const size = Math.trunc(bracketSize);
  const participants = Math.trunc(participantCount);
  if (size < 2 || size > 128 || (size & (size - 1)) !== 0
      || participants < 1 || participants > size) {
    throw new Error("TOURNAMENT_KNOCKOUT_TOPOLOGY_INVALID");
  }
  const roundCount = Math.log2(size);
  const rounds = Array.from({ length: roundCount }, (_, index) => {
    const order = index + 1;
    const matchCount = size / (2 ** order);
    const code = matchCount === 1 ? "FINAL"
      : matchCount === 2 ? "SEMIFINAL"
        : matchCount === 4 ? "QUARTERFINAL"
          : matchCount === 8 ? "ROUND_OF_16"
            : `ROUND_OF_${matchCount * 2}`;
    return { code, matchCount, order };
  });
  return {
    bracketSize: size,
    byes: size - participants,
    operationalMatches: participants - 1,
    participantCount: participants,
    roundCount,
    rounds,
    thirdPlaceMatches: thirdPlaceEnabled && size >= 4 ? 1 : 0,
  };
}

export function buildTournamentKnockoutReservationIntent(options: {
  durationMinutes: number;
  nodeId: string;
  startsAt: string;
  timezone: string;
  venueId?: string;
  venueLabel?: string;
}) {
  const startsAt = new Date(options.startsAt);
  const duration = Math.trunc(options.durationMinutes);
  if (!Number.isFinite(startsAt.getTime()) || duration < 10 || duration > 600
      || !options.timezone.trim() || !options.nodeId.trim()) {
    throw new Error("TOURNAMENT_KNOCKOUT_RESERVATION_INVALID");
  }
  return {
    endsAt: new Date(startsAt.getTime() + duration * 60_000).toISOString(),
    nodeId: options.nodeId,
    reason: "Reserva creada desde Tournament Hub",
    resourceKey: `knockout:${options.nodeId}`,
    startsAt: startsAt.toISOString(),
    timezone: options.timezone.trim(),
    ...(options.venueId?.trim() ? { venueId: options.venueId.trim() } : {}),
    ...(options.venueLabel?.trim() ? { venueLabel: options.venueLabel.trim() } : {}),
  };
}
