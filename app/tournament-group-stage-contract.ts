import {
  tournamentNumber,
  tournamentRecord,
  tournamentText,
  type TournamentJson,
} from "./tournament-draw-contract";

export const tournamentGroupStageActions = [
  "group_stage.prepare",
  "group_schedule.create",
  "group_schedule.generate",
  "group_schedule.validate",
  "group_schedule.publish",
  "group_stage.activate",
  "group_stage.complete",
  "qualification.rebuild",
  "qualification.validate",
  "qualification.publish",
  "bracket_template.create",
  "bracket_template.publish",
] as const;

export type TournamentGroupStageAction = typeof tournamentGroupStageActions[number];

export const tournamentGroupStageTabs = [
  "summary",
  "rounds",
  "matches",
  "standings",
  "teams",
  "discipline",
  "referees",
  "incidents",
  "rules",
  "bracket",
] as const;

export type TournamentGroupStageTab = typeof tournamentGroupStageTabs[number];

export const tournamentGroupStageRealtimeTable = "pachanga_tournament_invalidations" as const;
export const tournamentGroupStageReadCacheVersion = 2 as const;

export function isTournamentGroupStageAction(value: unknown): value is TournamentGroupStageAction {
  return typeof value === "string"
    && (tournamentGroupStageActions as readonly string[]).includes(value);
}

export function tournamentGroupStageRevision(snapshot: TournamentJson) {
  const groupStage = tournamentRecord(snapshot.groupStage);
  if (tournamentText(snapshot.kind) === "TournamentGroupStageSetup") {
    return tournamentNumber(
      snapshot.expectedRevision,
      tournamentNumber(tournamentRecord(snapshot.competition).tournamentRevision),
    );
  }
  return tournamentNumber(groupStage.revision);
}

export function tournamentGroupStageCacheOrder(snapshot: TournamentJson) {
  const cache = tournamentRecord(snapshot.cache);
  return {
    entityId: tournamentText(cache.entityId),
    revision: tournamentNumber(cache.revision),
    serverSequence: tournamentNumber(cache.serverSequence),
    updatedAt: tournamentText(cache.updatedAt),
  };
}

export function compareTournamentGroupStageSnapshots(left: TournamentJson, right: TournamentJson) {
  const a = tournamentGroupStageCacheOrder(left);
  const b = tournamentGroupStageCacheOrder(right);
  if (a.serverSequence !== b.serverSequence) return a.serverSequence - b.serverSequence;
  if (a.revision !== b.revision) return a.revision - b.revision;
  if (a.updatedAt !== b.updatedAt) return a.updatedAt.localeCompare(b.updatedAt);
  return a.entityId.localeCompare(b.entityId);
}

export type TournamentGroupStageSlotIntent = {
  endsAt: string;
  startsAt: string;
  timezone: string;
  venueId?: string;
  venueLabel?: string;
};

export function buildTournamentGroupStageSlotIntents(options: {
  fixtureCount: number;
  firstStartsAt: string;
  matchDurationMinutes: number;
  slotCadenceMinutes: number;
  timezone: string;
  venueLabel?: string;
}): TournamentGroupStageSlotIntent[] {
  const fixtureCount = Math.trunc(options.fixtureCount);
  const duration = Math.trunc(options.matchDurationMinutes);
  const cadence = Math.trunc(options.slotCadenceMinutes);
  const first = new Date(options.firstStartsAt);
  if (!Number.isFinite(first.getTime()) || fixtureCount < 1 || fixtureCount > 1000
      || duration < 10 || duration > 600 || cadence < duration || cadence > 10_080
      || !options.timezone.trim()) {
    throw new Error("TOURNAMENT_GROUP_SLOT_INTENT_INVALID");
  }
  return Array.from({ length: fixtureCount }, (_, index) => {
    const startsAt = new Date(first.getTime() + index * cadence * 60_000);
    const endsAt = new Date(startsAt.getTime() + duration * 60_000);
    return {
      endsAt: endsAt.toISOString(),
      startsAt: startsAt.toISOString(),
      timezone: options.timezone.trim(),
      ...(options.venueLabel?.trim() ? { venueLabel: options.venueLabel.trim() } : {}),
    };
  });
}
