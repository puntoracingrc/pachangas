import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  runTeamCosmeticRewardsSyntheticWorld,
  TEAM_COSMETIC_REWARD_MAPPINGS_V1,
} from "../simulation/synthetic-world/scripts/team-cosmetic-rewards-v1";

const migration = readFileSync(
  "supabase/migrations/20260811033931_team_cosmetic_rewards_v1.sql",
  "utf8",
);
const indexMigration = readFileSync(
  "supabase/migrations/20260811042657_team_cosmetic_rewards_fk_indexes.sql",
  "utf8",
);
const identityPage = readFileSync("app/equipo/identidad/page.tsx", "utf8");

test("Team Cosmetic Reward Policy V1 contains exactly the five approved mappings", () => {
  assert.deepEqual(TEAM_COSMETIC_REWARD_MAPPINGS_V1, [
    { achievementKey: "team.external.wins.001", cosmeticKey: "team.shield.border.copper", firstOccurrenceOnly: true, mappingKey: "first_challenge_win" },
    { achievementKey: "team.external.matches.010", cosmeticKey: "team.shield.ornament.banner", firstOccurrenceOnly: false, mappingKey: "ten_challenges" },
    { achievementKey: "team.matches.025", cosmeticKey: "team.shield.ornament.laurels", firstOccurrenceOnly: false, mappingKey: "twenty_five_matches" },
    { achievementKey: "team.matches.050", cosmeticKey: "team.shield.border.silver", firstOccurrenceOnly: false, mappingKey: "fifty_matches" },
    { achievementKey: "team.external.clean_sheets.001", cosmeticKey: "team.shield.effect.edge_glow", firstOccurrenceOnly: true, mappingKey: "first_clean_sheet" },
  ]);
  for (const mapping of TEAM_COSMETIC_REWARD_MAPPINGS_V1) {
    assert.match(migration, new RegExp(mapping.achievementKey.replaceAll(".", "\\.")));
    assert.match(migration, new RegExp(mapping.cosmeticKey.replaceAll(".", "\\.")));
  }
  assert.doesNotMatch(migration, /side_bolts|future_top|future_tournament|ornament\.crown/);
});

test("the policy is server-only, flag-gated and non-retroactive", () => {
  assert.match(migration, /private\.pachanga_team_cosmetic_rewards_enabled_v1\(\)/);
  assert.match(migration, /effective_from_server_sequence/);
  assert.match(migration, /selected_fact\.server_sequence <= selected_policy\.effective_from_server_sequence/);
  assert.match(migration, /selected_grant\.metric_value is distinct from selected_definition\.threshold/);
  assert.match(migration, /after insert on public\.pachanga_achievement_grants/);
  assert.match(migration, /revoke all on function private\.pachanga_apply_team_cosmetic_reward_v1\(uuid\)[\s\S]+from public, anon, authenticated/);
  assert.doesNotMatch(migration, /grant execute on function private\.pachanga_apply_team_cosmetic_reward_v1[^;]+authenticated/);
});

test("every reward foreign key reported by Supabase advisors has a covering index", () => {
  for (const column of [
    "achievement_definition_id",
    "cosmetic_key",
    "origin_match_fact_id",
    "policy_version",
  ]) {
    assert.match(indexMigration, new RegExp(`\\(${column}\\)`));
  }
  assert.doesNotMatch(indexMigration, /insert|update|delete|grant|reward.*trigger/i);
});

test("10 Retos gets a new active V3 authority row without reviving V1 or V2", () => {
  assert.match(migration, /'team\.external\.matches\.010', 3, 'Diez Retos'/);
  assert.match(migration, /'team', 'external', 'matches', 'TEAM_MATCHES'/);
  assert.match(migration, /activation_server_sequence/);
  assert.doesNotMatch(migration, /update public\.pachanga_achievement_definitions[\s\S]+version\s*[<=>]+\s*[12]/i);
});

test("direct team rewards never create team currency or personal cosmetic ownership", () => {
  assert.match(migration, /'currencyGranted', 0/);
  assert.doesNotMatch(migration, /insert into public\.pachanga_player_(?:points|reward|cosmetic)/i);
  assert.doesNotMatch(migration, /duplicatePoints|team points|team_currency/i);
});

test("reward notifications deep-link to the unlocked editor category", () => {
  assert.match(migration, /\/equipo\/identidad\?grupo=/);
  assert.match(migration, /&cosmetic=/);
  assert.match(identityPage, /handledTeamCosmeticDeepLinks/);
  assert.match(identityPage, /new URLSearchParams\(window\.location\.search\)\.get\("cosmetic"\)/);
  assert.match(identityPage, /setActiveShieldCategory\(item\.slot\)/);
});

test("Synthetic World exercises grants, replays, alreadyOwned and admin NEW isolation", () => {
  const result = runTeamCosmeticRewardsSyntheticWorld(250);
  assert.equal(result.teamCount, 250);
  assert.equal(result.eligibleAchievements, 1_250);
  assert.equal(result.grants, 1_225);
  assert.equal(result.alreadyOwned, 25);
  assert.equal(result.replayAttempts, 1_250);
  assert.equal(result.flagOffGrants, 0);
  assert.equal(result.notifications, result.grants * 2);
  assert.equal(result.unseenPerEligibleAdmin, result.grants * 2);
  assert.equal(result.lateAdminsWithoutHistoricalNew, 250);
  assert.equal(result.currencyGranted, 0);
  assert.equal(result.ratingV2Changes, 0);
  assert.equal(result.facetsChanges, 0);
  assert.equal(result.seasonScoreChanges, 0);
  assert.equal(result.topsChanges, 0);
});
