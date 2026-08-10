import type { SyntheticAttendanceRecord, SyntheticWorldState } from "./types";

export function normalizeSyntheticWorldState(state: SyntheticWorldState): SyntheticWorldState {
  const teams = state.teams.map((team) => ({ ...team, playerIds: [...new Set(team.playerIds)] }));
  const matches = new Map(state.matches.map((match) => [match.id, match]));
  const attendance = new Map<string, SyntheticAttendanceRecord>();
  for (const candidate of state.attendanceRecords) {
    const current = attendance.get(candidate.id);
    if (!current) {
      attendance.set(candidate.id, candidate);
      continue;
    }
    const participants = matches.get(candidate.matchId)?.participantIds ?? [];
    const candidatePlayed = candidate.finalOutcome === "played" && participants.includes(candidate.agentId);
    const currentPlayed = current.finalOutcome === "played" && participants.includes(current.agentId);
    if (candidatePlayed || !currentPlayed) attendance.set(candidate.id, candidate);
  }
  const cosmeticInventory = new Map(
    (state.playerCosmeticInventory ?? []).map((item) => [`${item.agentId}:${item.cosmeticKey}`, item]),
  );
  const cosmeticLoadouts = new Map(
    (state.playerCosmeticLoadouts ?? []).map((item) => [item.agentId, item]),
  );
  return {
    ...state,
    attendanceRecords: [...attendance.values()],
    playerCosmeticInventory: [...cosmeticInventory.values()],
    playerCosmeticLoadouts: [...cosmeticLoadouts.values()],
    teams,
  };
}
