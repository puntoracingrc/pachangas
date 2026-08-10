import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  EXTERNAL_RESULTS_CACHE_MAX_AGE_MS,
  externalMatchStateLabel,
  normalizeExternalMatch,
  normalizeExternalResultsSnapshot,
  readExternalResultsCache,
  writeExternalResultsCache,
} from "../app/external-results-contract";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";
import {
  TEAM_IDENTITY_CACHE_MAX_AGE_MS,
  normalizeProgressionSnapshot,
  normalizeTeamShieldSnapshot,
  opensPendingRewardSequence,
  readTeamIdentityCache,
  writeTeamIdentityCache,
} from "../app/team-identity-contract";

class MemoryStorage {
  readonly values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

function externalMatchFixture() {
  return {
    activeVersion: 2,
    autoConfirmationBlocked: true,
    awayTeam: { groupId: "group-b", levelSnapshot: 61, name: "Visitante", teamCode: "AWAY" },
    canonicalScoreAway: null,
    canonicalScoreHome: null,
    challengeId: "challenge-1",
    field: { address: "Carrer Major, 1", mapsUrl: null, name: "Camp", placeId: null },
    homeTeam: { groupId: "group-a", levelSnapshot: 63, name: "Local", teamCode: "HOME" },
    id: "external-1",
    modality: "futbol7",
    officialAt: null,
    officialVersion: null,
    participants: [{ cardSnapshot: { currentOverall: 67 }, groupId: "group-a", localPlayerId: "a1", name: "Ana", playerProfileId: "profile-a" }],
    pendingResponseFromGroupId: "group-a",
    proposedByGroupId: "group-b",
    responseDeadline: "2026-08-06T20:00:00.000Z",
    revision: 3,
    scheduledAt: "2026-08-03T20:00:00.000Z",
    scoreAway: 2,
    scoreHome: 3,
    scorers: [{ goals: 3, groupId: "group-a", localPlayerId: "a1" }],
    serverSequence: 41,
    side: "home",
    state: "change_proposed",
    unassignedAway: 0,
    unassignedHome: 0,
    updatedAt: "2026-08-03T21:00:00.000Z",
  };
}

function crestFixture() {
  const config = {
    backgroundKey: "team.shield.background.duotone",
    borderKey: "team.shield.border.clean",
    bottomOrnamentKey: null,
    effectKey: null,
    foundationYear: "",
    initials: "PIQ",
    patternKey: "team.shield.pattern.diagonal",
    primaryColorKey: "team.shield.color.midnight",
    primarySymbolKey: "team.shield.symbol.ball_iq",
    primarySymbolRotation: 0,
    primarySymbolScale: 1,
    schemaVersion: 1,
    secondaryColorKey: "team.shield.color.cyan",
    secondarySymbolKey: null,
    shapeKey: "team.shield.shape.classic_iq",
    sideOrnamentKey: null,
    topOrnamentKey: null,
  };
  return {
    canManage: true,
    catalog: [{ availability: "base", description: "Forma inicial", family: "shape", key: "team.shield.shape.classic_iq", name: "Clásico IQ", rarity: "common", render: { shape: "classic_iq" }, slot: "shape", unlocked: true }],
    confirmedRevision: 2,
    config,
    defaultConfig: config,
    group: { groupId: "group-a", name: "Pachangas A" },
    history: [],
    revision: 2,
    seenRevision: 1,
    serverSequence: 8,
    teamCosmeticRewardsEnabled: false,
    teamCosmeticsEnabled: true,
    unseenCount: 0,
    updatedAt: "2026-08-03T21:00:00.000Z",
  };
}

function progressionFixture() {
  return {
    catalogKey: "achievement_catalog_v2",
    confirmedRevision: 4,
    groupId: "group-a",
    groupRevision: 4,
    personalAchievementCatalog: [{
      awardedAt: null,
      category: "matches",
      currentValue: 3,
      description: "Participa en cinco partidos internos finalizados.",
      displayPriority: 15,
      family: "player.matches",
      firstAchievedAt: null,
      grantId: null,
      iconKey: "matches",
      key: "player.internal.matches.005",
      lastAchievedAt: null,
      occurrenceCount: 0,
      progressPercent: 60,
      rarity: "common",
      repeatable: false,
      rewardKey: null,
      rewardKind: "none",
      scope: "internal",
      shareDescription: "Cinco partidos confirmados.",
      shareTemplateKey: "player_milestone",
      shareTitle: "Uno de los nuestros",
      threshold: 5,
      title: "Uno de los nuestros",
      unlocked: false,
    }],
    personalAchievements: [],
    personalStats: [{
      appearances: 7, braces: 1, currentUnbeatenStreak: 2, currentWinStreak: 1,
      distinctOpponents: 3, distinctOpponentsWon: 2, doubleHatTricks: 0,
      draws: 2, goals: 6, hatTricks: 1, losses: 2, maxUnbeatenStreak: 4,
      maxWinStreak: 2, pokers: 0, repokers: 0, revision: 4, scope: "all",
      updatedAt: "2026-08-03T21:00:00.000Z", wins: 3,
    }],
    rewardEconomy: {
      account: { balance: 15, lifetimeEarned: 15, lifetimeSpent: 0, revision: 2, serverSequence: 20, updatedAt: "2026-08-03T21:00:00.000Z" },
      boxCatalog: [{ animationKey: "reward_box_blue", boxType: "collective.common", catalogVersion: 1, maxPoints: 7, minPoints: 4, name: "Caja común", possibleRewards: [{ kind: "points", weight: 70 }], presentationKey: "box.common", rarity: "common" }],
      currencyKey: "player_points",
      inventory: [{ acquiredAt: "2026-08-03T21:00:00.000Z", key: "symbol.ball", kind: "player_cosmetic", metadata: {}, sourceBoxId: "box-0", state: "unlocked" }],
      ledger: [{ achievementGrantId: "grant-0", balanceAfter: 15, createdAt: "2026-08-03T21:00:00.000Z", delta: 15, id: "ledger-1", matchFactId: "fact-0", metadata: {}, serverSequence: 20, sourceBoxId: "box-0", sourceType: "reward_box" }],
    },
    rewards: [{
      achievement: { awardedAt: "2026-08-03T21:00:00.000Z", description: "Primer partido", isFirst: true, key: "team.external.matches.001", occurredAt: "2026-08-03T20:00:00.000Z", rarity: "common", sequenceCount: 1, title: "Primer rival" },
      animationKey: "reward_box_blue",
      boxId: "box-1",
      boxRarity: "uncommon",
      boxType: "collective.uncommon",
      economyVersion: 1,
      generatedAt: "2026-08-03T21:00:00.000Z",
      matchFactId: "fact-1",
      openedAt: null,
      recipientRevision: 1,
      rewardGrantedAt: null,
      rewardGrantId: "reward-1",
      rewardKey: "box.collective.common",
      rewardKind: "collective_box",
      rewardPayload: null,
      rewardPoolKey: "pool.collective.uncommon",
      presentationKey: "box.uncommon",
      sourceCorrection: null,
      status: "pending",
    }],
    serverSequence: 19,
    teamAchievements: [],
    teamAchievementCatalog: [{
      animationKey: "reward_box_blue", boxRarity: "common", category: "matches",
      currentValue: 3, description: "Cinco partidos", displayPriority: 15,
      family: "team.external.matches", iconKey: "matches",
      key: "team.external.matches.005", presentationKey: "box.common",
      rarity: "common", repeatable: false, rewardPoolVersion: 1,
      scope: "external", threshold: 5, title: "Cinco rivales",
    }],
    teamStats: [{
      bigWins: 1, cleanSheets: 2, closeWins: 1, currentUnbeatenStreak: 2,
      currentWinStreak: 1, distinctOpponents: 3, distinctOpponentsWon: 2,
      draws: 1, goalsAgainst: 5, goalsFor: 9, losses: 1, matches: 5,
      maxUnbeatenStreak: 3, maxWinStreak: 2, revision: 4, scope: "external",
      updatedAt: "2026-08-03T21:00:00.000Z", wins: 3,
    }],
    updatedAt: "2026-08-03T21:00:00.000Z",
    userRevision: 2,
  };
}

test("normalizes canonical external matches without inventing invalid numeric values", () => {
  const normalized = normalizeExternalMatch(externalMatchFixture());
  assert.ok(normalized);
  assert.equal(normalized.revision, 3);
  assert.equal(normalized.state, "change_proposed");
  assert.equal(normalized.participants[0]?.cardSnapshot.currentOverall, 67);
  assert.equal(normalized.scorers[0]?.goals, 3);

  const invalidNumbers = normalizeExternalMatch({
    ...externalMatchFixture(),
    activeVersion: "not-a-number",
    canonicalScoreHome: "not-a-number",
    homeTeam: { ...externalMatchFixture().homeTeam, levelSnapshot: "not-a-number" },
  });
  assert.ok(invalidNumbers);
  assert.equal(invalidNumbers.activeVersion, null);
  assert.equal(invalidNumbers.canonicalScoreHome, null);
  assert.equal(invalidNumbers.homeTeam.levelSnapshot, null);
  assert.equal(externalMatchStateLabel("auto_confirmed"), "Autoconfirmado");
});

test("derived caches are scoped, finite and never manufacture canonical state", () => {
  const storage = new MemoryStorage();
  const external = normalizeExternalResultsSnapshot({
    canManage: true,
    confirmedRevision: 3,
    groupId: "group-a",
    groupName: "Pachangas A",
    matches: [externalMatchFixture()],
    roster: [{ active: true, currentOverall: 67, localPlayerId: "a1", name: "Ana", playerProfileId: "profile-a", position: "DEL" }],
    serverSequence: 41,
    updatedAt: "2026-08-03T21:00:00.000Z",
  });
  const crest = normalizeTeamShieldSnapshot(crestFixture());
  const progression = normalizeProgressionSnapshot(progressionFixture());
  assert.ok(external && crest && progression);

  writeExternalResultsCache(storage, "user-a", "group-a", external, 1_000);
  writeTeamIdentityCache(storage, "user-a", "group-a", crest, progression, 1_000);
  assert.equal(readExternalResultsCache(storage, "user-a", "group-a", 1_001)?.serverSequence, 41);
  assert.equal(readExternalResultsCache(storage, "user-b", "group-a", 1_001), null);
  assert.equal(readTeamIdentityCache(storage, "user-a", "group-a", 1_001)?.shield?.revision, 2);
  assert.equal(progression.personalAchievementCatalog[0]?.progressPercent, 60);
  assert.equal(progression.personalAchievementCatalog[0]?.unlocked, false);
  assert.equal(progression.catalogKey, "achievement_catalog_v2");
  assert.equal(progression.personalStats[0]?.scope, "all");
  assert.equal(progression.personalStats[0]?.distinctOpponents, 3);
  assert.equal(progression.teamStats[0]?.cleanSheets, 2);
  assert.equal(progression.teamAchievementCatalog[0]?.boxRarity, "common");
  assert.equal(progression.rewardEconomy.account.balance, 15);
  assert.equal(progression.rewardEconomy.inventory[0]?.key, "symbol.ball");
  assert.equal(progression.rewards[0]?.boxType, "collective.uncommon");
  assert.equal(readTeamIdentityCache(storage, "user-a", "group-b", 1_001), null);
  assert.equal(readExternalResultsCache(storage, "user-a", "group-a", 1_000 + EXTERNAL_RESULTS_CACHE_MAX_AGE_MS + 1), null);
  assert.equal(readTeamIdentityCache(storage, "user-a", "group-a", 1_000 + TEAM_IDENTITY_CACHE_MAX_AGE_MS + 1), null);
});

test("every reward notification deep link opens the complete pending sequence", () => {
  assert.equal(opensPendingRewardSequence("?grupo=group-a&rewards=pending"), true);
  assert.equal(opensPendingRewardSequence("?reward=legacy-grant"), true);
  assert.equal(opensPendingRewardSequence("?grupo=group-a&achievements=latest"), false);
  assert.equal(opensPendingRewardSequence("?grupo=group-a"), false);

  const identityUi = readFileSync(new URL("../app/equipo/identidad/page.tsx", import.meta.url), "utf8");
  assert.match(identityUi, /handledRewardDeepLinks/);
  assert.match(identityUi, /addEventListener\("pachangas:reward-deep-link"/);
  assert.match(identityUi, /handledRewardDeepLinks\.current\.delete\(selectedGroupId\)/);
  assert.match(identityUi, /canonical\.rewards\.filter\(\(reward\) => reward\.status === "pending"\)/);
});

test("the PWA bridge classifies every new mutation and leaves canonical reads available", () => {
  const endpoint = "https://demo.supabase.co/rest/v1/rpc/";
  const writes = [
    "cancel_pachanga_external_match_v1",
    "complete_pachanga_external_scorers_v1",
    "confirm_pachanga_external_result_v1",
    "open_pachanga_reward_box_v2",
    "open_pachanga_reward_v1",
    "propose_pachanga_external_result_change_v1",
    "publish_pachanga_external_result_v1",
    "publish_pachanga_team_crest_v1",
    "reject_pachanga_external_result_change_v1",
    "save_pachanga_team_crest_draft_v1",
    "save_pachanga_team_shield_loadout_v1",
    "mark_pachanga_team_cosmetics_seen_v1",
  ];
  for (const rpc of writes) {
    assert.equal(classifySupabaseWrite(`${endpoint}${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  for (const rpc of [
    "get_pachanga_external_results_snapshot_v1",
    "get_pachanga_progression_snapshot_v1",
    "get_pachanga_team_crest_snapshot_v1",
    "get_pachanga_team_shield_snapshot_v1",
  ]) {
    assert.equal(classifySupabaseWrite(`${endpoint}${rpc}`, { method: "POST" }), null);
  }
});

test("external result SQL is bilateral, revisioned, idempotent and canonical", () => {
  const sql = readFileSync(new URL("../supabase/migrations/20260804023455_external_match_results_mvp.sql", import.meta.url), "utf8");
  assert.match(sql, /create table if not exists public\.pachanga_external_matches/);
  assert.match(sql, /create table if not exists public\.pachanga_external_result_versions/);
  assert.match(sql, /create table if not exists public\.pachanga_external_result_operation_receipts/);
  assert.match(sql, /state in \([\s\S]*'draft'[\s\S]*'pending_rival'[\s\S]*'change_proposed'[\s\S]*'confirmed'[\s\S]*'auto_confirmed'[\s\S]*'disputed'[\s\S]*'cancelled'/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\('external-result-operation:'/);
  assert.match(sql, /if selected\.revision <> expected_revision/);
  assert.match(sql, /using errcode = 'PT409'/);
  assert.match(sql, /Scorer must be a participant of the acting team/);
  assert.match(sql, /Own scorers must add up exactly to the team score/);
  assert.match(sql, /target_final_state = 'auto_confirmed'/);
  assert.match(sql, /selected\.state in \('change_proposed', 'needs_scorer_fix'\)/);
  assert.match(sql, /jsonb_build_object\('reason', 'change_response_expired'\)/);
  assert.match(sql, /for update skip locked/);
  assert.match(sql, /order by matches\.response_deadline, matches\.id/);
  assert.match(sql, /alter publication supabase_realtime[\s\S]*pachanga_external_match_group_state/);
  assert.doesNotMatch(sql, /grant (insert|update|delete|all) on table public\.pachanga_external_matches to authenticated/i);
});

test("achievement evaluators are typed and rewards are decided before opening", () => {
  const sql = readFileSync(new URL("../supabase/migrations/20260804023520_achievement_reward_engine_mvp.sql", import.meta.url), "utf8");
  assert.equal(sql.match(/\('team\.internal\./g)?.length, 10);
  assert.equal(sql.match(/\('team\.external\./g)?.length, 20);
  assert.equal(sql.match(/\('player\.internal\./g)?.length, 6);
  assert.equal(sql.match(/\('player\.external\./g)?.length, 6);
  assert.match(sql, /evaluator_key in \([\s\S]*'TEAM_MATCHES'[\s\S]*'PLAYER_HATTRICKS'/);
  assert.doesNotMatch(sql, /execute\s+format|evaluator_sql|condition_sql/i);
  assert.match(sql, /'deterministic', true/);
  assert.match(sql, /insert into public\.pachanga_reward_recipients/);
  assert.match(sql, /select distinct on \(members\.user_id\)/);
  assert.match(sql, /where recipients\.user_id = auth\.uid\(\)/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\(\s*'reward-open:'/);
  assert.match(sql, /pachanga_progression_match_fact_sequence_idx[\s\S]*server_sequence, group_id/);
  assert.match(sql, /order by events\.server_sequence desc, events\.id desc/);
  assert.match(sql, /'\/equipo\/identidad\?reward='/);
});

test("individual achievement catalog adds canonical milestones and exact doubles", () => {
  const sql = readFileSync(new URL("../supabase/migrations/20260808175351_individual_achievements_catalog_v1.sql", import.meta.url), "utf8");
  assert.match(sql, /'player\.internal\.matches\.005', 'Uno de los nuestros'/);
  assert.match(sql, /'player\.internal\.matches\.025', 'Habitual'/);
  assert.match(sql, /player_facts\.goals = 2\)::integer as braces/);
  assert.match(sql, /player_facts\.goals >= 3\)::integer as hat_tricks/);
  assert.match(sql, /'personalAchievementCatalog'/);
  assert.match(sql, /'progressPercent'/);
  assert.match(sql, /private\.pachanga_progression_snapshot_base_v1/);
  assert.match(sql, /grant execute on function public\.get_pachanga_progression_snapshot_v1\(uuid\)[\s\S]*to authenticated/);
  assert.doesNotMatch(sql, /execute\s+format|evaluator_sql|condition_sql/i);
  assert.doesNotMatch(sql, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /calibrated_(overall|facets)\s*=/i);
});

test("collective boxes separate personal recognition, team occurrences and sealed rewards", () => {
  const sql = readFileSync(new URL("../supabase/migrations/20260808175352_collective_reward_boxes_v2.sql", import.meta.url), "utf8");
  assert.match(sql, /set reward_kind = 'none', reward_key = null[\s\S]*subject_type = 'player'/);
  assert.match(sql, /'PLAYER_POKERS'[\s\S]*'PLAYER_REPOKERS'[\s\S]*'PLAYER_DOUBLE_HAT_TRICKS'/);
  assert.match(sql, /'ruleKind', 'player_match_goals'/);
  assert.match(sql, /order by definitions\.threshold desc[\s\S]*limit 1/);
  assert.match(sql, /'ruleKind', 'team_match_goals'/);
  assert.match(sql, /create table if not exists private\.pachanga_reward_box_contents/);
  assert.match(sql, /revoke all on table private\.pachanga_reward_box_contents[\s\S]*authenticated/);
  assert.match(sql, /from public\.pachanga_progression_player_match_facts player_facts[\s\S]*player_facts\.state = 'active'/);
  assert.match(sql, /create or replace function public\.open_pachanga_reward_box_v2/);
  assert.match(sql, /if selected\.revision <> expected_revision/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\([\s\S]*'reward-box-open:'/);
  assert.match(sql, /'postmatch_reward_boxes'[\s\S]*'Tus premios del partido están listos'/);
  assert.match(sql, /'\/equipo\/identidad\?grupo='[\s\S]*'&rewards=pending'/);
  assert.match(sql, /openedBoxesPreserved/);
  assert.doesNotMatch(sql, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /calibrated_(overall|facets)\s*=/i);
});

test("reward economy is versioned, sealed, auditable and inaccessible to direct client writes", () => {
  const sql = readFileSync(new URL("../supabase/migrations/20260808175354_reward_economy_v1.sql", import.meta.url), "utf8");
  for (const table of [
    "pachanga_reward_economy_versions",
    "pachanga_reward_box_catalog",
    "pachanga_reward_pool_catalog",
    "pachanga_achievement_box_rules",
    "pachanga_player_point_accounts",
    "pachanga_player_points_ledger",
  ]) assert.match(sql, new RegExp(`create table if not exists public\\.${table}`));
  for (const rarity of ["common", "uncommon", "rare", "epic", "legendary"]) {
    assert.match(sql, new RegExp(`'collective\\.${rarity}'`));
  }
  assert.match(sql, /private\.pachanga_seal_reward_box_v1/);
  assert.match(sql, /entropy uuid := gen_random_uuid\(\)/);
  assert.match(sql, /Sealed reward box contents are immutable/);
  assert.match(sql, /catalogVersion[\s\S]*poolEntryKey[\s\S]*duplicateConversionPoints/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\([\s\S]*'player-points:'/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\([\s\S]*'reward-box-open:'/);
  assert.match(sql, /on conflict \(player_profile_id, reward_kind, reward_key\) do nothing/);
  assert.match(sql, /'duplicateConverted'/);
  assert.match(sql, /'rewardEconomy'/);
  assert.match(sql, /revoke all on table public\.pachanga_player_points_ledger[\s\S]*authenticated/);
  assert.match(sql, /revoke all on function private\.pachanga_apply_player_points_v1/);
  assert.doesNotMatch(sql, /grant (insert|update|delete|all) on table public\.pachanga_player_points_ledger to authenticated/i);
  assert.doesNotMatch(sql, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /calibrated_(overall|facets)\s*=/i);
  assert.doesNotMatch(sql, /stripe_(secret|checkout)|google play billing|service_role_key/i);
});

test("crest SQL provides five base shapes, immutable versions and server-side unlock checks", () => {
  const sql = readFileSync(new URL("../supabase/migrations/20260804023534_team_crest_identity_mvp.sql", import.meta.url), "utf8");
  assert.match(sql, /create table if not exists public\.pachanga_team_crest_drafts/);
  assert.match(sql, /create table if not exists public\.pachanga_team_crest_versions/);
  assert.match(sql, /Published crest versions are immutable/);
  assert.match(sql, /Only team administrators can edit the official crest/);
  assert.match(sql, /Only team administrators can publish the official crest/);
  assert.match(sql, /COSMETIC_LOCKED:/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\('team-crest-operation:'/);
  assert.match(sql, /alter publication supabase_realtime add table public\.pachanga_team_crest_state/);
  assert.doesNotMatch(sql, /grant (insert|update|delete|all) on table public\.pachanga_team_crest_versions to authenticated/i);

  const achievementsSql = readFileSync(new URL("../supabase/migrations/20260804023520_achievement_reward_engine_mvp.sql", import.meta.url), "utf8");
  assert.equal(achievementsSql.match(/\('shape\.(classic|rounded|pointed|circle|banner)'/g)?.length, 5);
});

test("new migrations consume Rating V2 snapshots without redefining or mutating Rating V2", () => {
  const newSql = [
    "20260804023455_external_match_results_mvp.sql",
    "20260804023520_achievement_reward_engine_mvp.sql",
    "20260804023534_team_crest_identity_mvp.sql",
    "20260808175354_reward_economy_v1.sql",
  ].map((name) => readFileSync(new URL(`../supabase/migrations/${name}`, import.meta.url), "utf8")).join("\n");
  assert.match(newSql, /from public\.pachanga_match_rating_participants/);
  assert.match(newSql, /on public\.pachanga_match_rating_snapshots/);
  assert.doesNotMatch(newSql, /create or replace function public\.finalize_pachanga_match_authoritative_v2/i);
  assert.doesNotMatch(newSql, /create or replace function public\.(submit_pachanga_player_rating_v2|complete_pachanga_player_initial_assessment)/i);
  assert.doesNotMatch(newSql, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(newSql, /insert into public\.pachanga_rating_evidence/i);
  assert.doesNotMatch(newSql, /calibrated_facets\s*=/i);

  const revocationSql = readFileSync(new URL("../supabase/migrations/20260803053632_rating_v2_profile_authority.sql", import.meta.url), "utf8");
  assert.match(revocationSql, /revoke all on function public\.append_pachanga_player_rating\(uuid, text, jsonb\)/);
  assert.match(revocationSql, /revoke all on function public\.complete_pachanga_player_initial_assessment/);
  assert.match(revocationSql, /revoke all on function public\.complete_pachanga_player_advanced_assessment/);
});

test("client surfaces write only through RPC and subscribe to revision rows", () => {
  const externalUi = readFileSync(new URL("../app/mercado/external-results-panel.tsx", import.meta.url), "utf8");
  const identityUi = readFileSync(new URL("../app/equipo/identidad/page.tsx", import.meta.url), "utf8");
  assert.match(externalUi, /\.rpc\("publish_pachanga_external_result_v1"/);
  assert.match(externalUi, /table: "pachanga_external_match_group_state"/);
  assert.match(identityUi, /\.rpc\("save_pachanga_team_shield_loadout_v1"/);
  assert.match(identityUi, /target_config: draftDesign/);
  assert.match(identityUi, /table: "pachanga_team_shield_state"/);
  assert.doesNotMatch(identityUi, /\.rpc\("save_pachanga_team_crest_draft_v1"/);
  assert.doesNotMatch(identityUi, /\.rpc\("publish_pachanga_team_crest_v1"/);
  assert.match(identityUi, /\.rpc\("open_pachanga_reward_box_v2"/);
  assert.match(identityUi, /beginRewardSequence\(pendingRewards\)/);
  assert.match(identityUi, /table: "pachanga_progression_group_state"/);
  assert.match(identityUi, /table: "pachanga_progression_user_state"/);
  assert.doesNotMatch(externalUi, /\.from\("pachanga_external_[^"]+"\)\s*\.(insert|update|delete)/);
  assert.doesNotMatch(identityUi, /\.from\("pachanga_(achievement|reward|team_crest)[^"]+"\)\s*\.(insert|update|delete)/);
});
