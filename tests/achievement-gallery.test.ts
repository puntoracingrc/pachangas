import assert from "node:assert/strict";
import test from "node:test";
import { achievementProgress, type AchievementDefinition } from "../app/personalizar-carta/achievement-gallery-model";
const definition: AchievementDefinition = { id: "goals", achievement_key: "player.all.goals.005", title: "Goleador", description: "Marca cinco goles", rarity: "common", match_scope: "all", evaluator_key: "PLAYER_GOALS", threshold: 5, repeatable: false };

test("progress uses the matching server scope without adding internal and external twice", () => {
  const result = achievementProgress(definition, [{ match_scope: "all", goals: 4 }, { match_scope: "internal", goals: 3 }, { match_scope: "external", goals: 1 }], []);
  assert.equal(result.current, 4);
  assert.equal(result.percent, 80);
  assert.equal(result.unlocked, false);
});
test("reaching the target does not invent an unlock and revoked grants do not count", () => {
  const result = achievementProgress(definition, [{ match_scope: "all", goals: 100 }], [{ definition_id: "goals", state: "revoked" }, { definition_id: "other", state: "active" }]);
  assert.equal(result.percent, 100);
  assert.equal(result.unlocked, false);
  assert.equal(result.occurrences, 0);
});
test("active repeated grants are recognised independently of missing stats", () => {
  const result = achievementProgress({ ...definition, repeatable: true }, [], [{ definition_id: "goals", state: "active" }, { definition_id: "goals", state: "active" }]);
  assert.equal(result.unlocked, true);
  assert.equal(result.occurrences, 2);
  assert.equal(result.percent, 100);
});
test("distinct opponents and scoring feats use their own canonical counters", () => {
  assert.equal(achievementProgress({ ...definition, evaluator_key: "PLAYER_DISTINCT_OPPONENT_WINS" }, [{ match_scope: "all", wins: 80, distinct_opponents_won: 3 }], []).current, 3);
  assert.equal(achievementProgress({ ...definition, evaluator_key: "PLAYER_DOUBLE_HAT_TRICKS" }, [{ match_scope: "all", goals: 200, double_hat_tricks: 2 }], []).current, 2);
  assert.equal(achievementProgress({ ...definition, evaluator_key: "NEW_UNKNOWN_RULE" }, [], []).current, null);
});

test("server-aggregated repetitions are not capped by API pagination", () => {
  const result = achievementProgress(definition, [], [{definition_id: "goals", state: "active", occurrences: 1501}]);
  assert.equal(result.occurrences, 1501);
  assert.equal(result.unlocked, true);
});

test("team progress uses team counters and only the definition's match scope", () => {
  const teamDefinition = { ...definition, evaluator_key: "TEAM_GOALS", match_scope: "external" };
  const stats = [{ match_scope: "all", goals_for: 80 }, { match_scope: "external", goals_for: 3, wins: 20, big_wins: 1, distinct_opponents_won: 2 }];
  const pending = achievementProgress(teamDefinition, stats, [{ definition_id: definition.id, state: "revoked" }]);
  assert.equal(pending.current, 3);
  assert.equal(pending.percent, 60);
  assert.equal(pending.unlocked, false);
  assert.equal(achievementProgress({ ...teamDefinition, evaluator_key: "TEAM_BIG_WINS" }, stats, []).current, 1);
  assert.equal(achievementProgress({ ...teamDefinition, evaluator_key: "TEAM_DISTINCT_OPPONENT_WINS" }, stats, []).current, 2);
  assert.equal(achievementProgress({ ...teamDefinition, evaluator_key: "TEAM_MATCHES" }, [{ match_scope: "external", matches_played: 4 }], []).current, 4);
  assert.equal(achievementProgress({ ...teamDefinition, evaluator_key: "TEAM_MAX_WIN_STREAK" }, [{ match_scope: "external", max_win_streak: 3, current_win_streak: 0 }], []).current, 3);
});
