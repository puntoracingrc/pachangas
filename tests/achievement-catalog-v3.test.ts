import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { resolveGoalRewardComponents, summarizeComponents } from "./achievement-catalog-v3-model";

const migration = readFileSync(new URL(
  "../supabase/migrations/20260808205638_achievement_catalog_v3.sql",
  import.meta.url,
), "utf8");
const identityUi = readFileSync(new URL("../app/equipo/identidad/page.tsx", import.meta.url), "utf8");
const contract = readFileSync(new URL("../app/team-identity-contract.ts", import.meta.url), "utf8");

const expected = new Map<number, Record<string, number>>([
  [1, {}],
  [2, { doblete: 1 }],
  [3, { hat_trick: 1 }],
  [4, { poker: 1 }],
  [5, { manita: 1 }],
  [6, { hat_trick: 2 }],
  [7, { doblete: 1, manita: 1 }],
  [8, { poker: 2 }],
  [9, { hat_trick: 3 }],
  [10, { manita: 2 }],
  [11, { hat_trick: 2, manita: 1 }],
  [12, { doblete: 1, manita: 2 }],
  [13, { hat_trick: 1, manita: 2 }],
  [14, { manita: 2, poker: 1 }],
  [15, { manita: 3 }],
  [16, { hat_trick: 2, manita: 2 }],
  [17, { doblete: 1, manita: 3 }],
  [18, { manita: 2, poker: 2 }],
  [19, { hat_trick: 3, manita: 2 }],
  [20, { manita: 4 }],
]);

test("collective goals 1 through 20 resolve to the approved exact components", () => {
  for (const [goals, expectedSummary] of expected) {
    const components = resolveGoalRewardComponents(goals);
    assert.deepEqual(summarizeComponents(components), expectedSummary, `${goals} goals`);
    assert.equal(components.reduce((sum, component) => sum + component.goals, 0), goals === 1 ? 0 : goals);
  }
});

test("all values above ten remain exactly representable without a remainder of one", () => {
  for (let goals = 11; goals <= 250; goals += 1) {
    const components = resolveGoalRewardComponents(goals);
    assert.equal(components.reduce((sum, component) => sum + component.goals, 0), goals);
    assert.ok(components.every((component) => component.goals >= 2));
  }
});

test("catalog V3 preserves V2 individuals and replaces only collective progress", () => {
  assert.match(migration, /catalog_key = 'achievement_catalog_v2'\s+and subject_type = 'team'/);
  assert.match(migration, /family_key in \('team\.internal\.matches', 'team\.external\.matches'\)\s+then 'DEPRECATE'/);
  assert.match(migration, /'achievement_catalog_v3', 'team\.matches'/);
  assert.match(migration, /\(500, 'Quinientos partidos', 'legendary'/);
  assert.doesNotMatch(migration, /update public\.pachanga_player_profiles/i);
});

test("component idempotency and independent boxes are enforced in PostgreSQL", () => {
  assert.match(migration, /primary key \(reward_grant_id, user_id, component_index\)/);
  assert.match(migration, /achievement_grant_id, user_id, component_index/);
  assert.match(migration, /jsonb_array_elements\(components\) with ordinality/);
  assert.match(migration, /on conflict \(achievement_grant_id, user_id, component_index\)/);
  assert.doesNotMatch(migration, /max_boxes_per_match/i);
});

test("Dominio absoluto is additive, Reto-only and stricter than a clean sheet", () => {
  assert.match(migration, /'team\.external\.absolute_dominance\.001'.*'Dominio absoluto'/s);
  assert.match(migration, /target_match_scope = 'external'\s+and match_fact\.outcome = 'win'\s+and match_fact\.big_win\s+and match_fact\.goals_against = 0/);
  assert.match(migration, /when 'team_match_clean_sheet' then source\.clean_sheet/);
  assert.doesNotMatch(migration, /team_match_clean_sheet[^\n]*goals_for\s*>\s*0/);
});

test("the client consumes canonical components and calls external matches Retos", () => {
  assert.match(contract, /componentIndex: number/);
  assert.match(contract, /rewardComponent: RewardComponent \| null/);
  assert.match(contract, /scope: MatchScope/);
  const statistics = readFileSync(new URL("../app/personalizar-carta/progression-statistics.tsx", import.meta.url), "utf8");
  assert.match(statistics, /\["external", "Retos"\]/);
  assert.match(identityUi, /rewardComponent\?\.label/);
});
