import type { PlayerCosmeticRarity } from "../player-cosmetics-contract";

export type AchievementDefinition = {
  id: string;
  achievement_key: string;
  title: string;
  description: string;
  rarity: PlayerCosmeticRarity;
  match_scope: string;
  evaluator_key: string;
  threshold: number;
  repeatable: boolean;
};
export type AchievementGrant = { definition_id: string; state: string; occurrences?: number };
export type AchievementStats = { match_scope: string; [key: string]: string | number };

// Display the server's cumulative metrics. Only an active grant proves unlock.
const metrics: Record<string, string> = {
  TEAM_MATCHES: "matches_played", TEAM_WINS: "wins", TEAM_DRAWS: "draws", TEAM_LOSSES: "losses",
  TEAM_GOALS: "goals_for", TEAM_CLEAN_SHEETS: "clean_sheets", TEAM_BIG_WINS: "big_wins",
  TEAM_CLOSE_WINS: "close_wins", TEAM_SCORELESS_DRAWS: "scoreless_draws",
  TEAM_MAX_WIN_STREAK: "max_win_streak", TEAM_MAX_UNBEATEN_STREAK: "max_unbeaten_streak",
  TEAM_DISTINCT_OPPONENTS: "distinct_opponents", TEAM_DISTINCT_OPPONENT_WINS: "distinct_opponents_won",
  PLAYER_APPEARANCES: "appearances", PLAYER_WINS: "wins", PLAYER_GOALS: "goals",
  PLAYER_BRACES: "braces", PLAYER_HATTRICKS: "hat_tricks", PLAYER_POKERS: "pokers",
  PLAYER_REPOKERS: "repokers", PLAYER_DOUBLE_HAT_TRICKS: "double_hat_tricks",
  PLAYER_MAX_WIN_STREAK: "max_win_streak", PLAYER_MAX_UNBEATEN_STREAK: "max_unbeaten_streak",
  PLAYER_DISTINCT_OPPONENTS: "distinct_opponents", PLAYER_DISTINCT_OPPONENT_WINS: "distinct_opponents_won",
};

export function achievementProgress(definition: AchievementDefinition, stats: AchievementStats[], grants: AchievementGrant[]) {
  const occurrences = grants.filter(grant => grant.definition_id === definition.id && grant.state === "active")
    .reduce((total, grant) => total + Math.max(1, Number(grant.occurrences) || 1), 0);
  const metric = metrics[definition.evaluator_key];
  const row = stats.find(item => item.match_scope === definition.match_scope);
  const current = metric ? Math.max(0, Number(row?.[metric]) || 0) : null;
  const target = Math.max(1, Number(definition.threshold) || 1);
  return { unlocked: occurrences > 0, occurrences, current, target,
    percent: occurrences ? 100 : current == null ? 0 : Math.min(100, Math.floor(current * 100 / target)) };
}
