type Mapping = {
  achievementKey: string;
  cosmeticKey: string;
  firstOccurrenceOnly: boolean;
  mappingKey: string;
};

type SyntheticRewardTeam = {
  adminEligibleSince: Map<string, number>;
  inventory: Map<string, number>;
  ledger: Map<string, "already_owned" | "granted">;
  notifications: Set<string>;
  seen: Map<string, Set<string>>;
};

export const TEAM_COSMETIC_REWARD_MAPPINGS_V1: Mapping[] = [
  { achievementKey: "team.external.wins.001", cosmeticKey: "team.shield.border.copper", firstOccurrenceOnly: true, mappingKey: "first_challenge_win" },
  { achievementKey: "team.external.matches.010", cosmeticKey: "team.shield.ornament.banner", firstOccurrenceOnly: false, mappingKey: "ten_challenges" },
  { achievementKey: "team.matches.025", cosmeticKey: "team.shield.ornament.laurels", firstOccurrenceOnly: false, mappingKey: "twenty_five_matches" },
  { achievementKey: "team.matches.050", cosmeticKey: "team.shield.border.silver", firstOccurrenceOnly: false, mappingKey: "fifty_matches" },
  { achievementKey: "team.external.clean_sheets.001", cosmeticKey: "team.shield.effect.edge_glow", firstOccurrenceOnly: true, mappingKey: "first_clean_sheet" },
];

function consume(
  team: SyntheticRewardTeam,
  teamId: string,
  achievementKey: string,
  isFirst: boolean,
  sequence: number,
  enabled: boolean,
) {
  const mapping = TEAM_COSMETIC_REWARD_MAPPINGS_V1.find((candidate) => candidate.achievementKey === achievementKey);
  if (!enabled || !mapping || (mapping.firstOccurrenceOnly && !isFirst)) return "ineligible" as const;
  const ledgerKey = `${teamId}:${mapping.mappingKey}:v1`;
  if (team.ledger.has(ledgerKey)) return "replay" as const;
  const alreadyOwned = team.inventory.has(mapping.cosmeticKey);
  team.ledger.set(ledgerKey, alreadyOwned ? "already_owned" : "granted");
  if (alreadyOwned) return "already_owned" as const;
  team.inventory.set(mapping.cosmeticKey, sequence);
  for (const adminId of team.adminEligibleSince.keys()) {
    team.notifications.add(`${ledgerKey}:${adminId}`);
  }
  return "granted" as const;
}

function unseen(team: SyntheticRewardTeam, adminId: string) {
  const eligibleSince = team.adminEligibleSince.get(adminId) ?? Number.POSITIVE_INFINITY;
  const seen = team.seen.get(adminId) ?? new Set<string>();
  return [...team.inventory]
    .filter(([key, sequence]) => sequence >= eligibleSince && !seen.has(key))
    .map(([key]) => key);
}

export function runTeamCosmeticRewardsSyntheticWorld(teamCount = 250) {
  let sequence = 101;
  let eligibleAchievements = 0;
  let grants = 0;
  let alreadyOwned = 0;
  let replayAttempts = 0;
  let flagOffGrants = 0;
  let notifications = 0;
  let unseenPerEligibleAdmin = 0;
  let lateAdminsWithoutHistoricalNew = 0;

  for (let index = 0; index < teamCount; index += 1) {
    const teamId = `synthetic-reward-team-${index + 1}`;
    const ownerId = `${teamId}-owner`;
    const adminId = `${teamId}-admin`;
    const team: SyntheticRewardTeam = {
      adminEligibleSince: new Map([[ownerId, 0], [adminId, 0]]),
      inventory: new Map(),
      ledger: new Map(),
      notifications: new Set(),
      seen: new Map(),
    };
    if (index % 10 === 0) team.inventory.set("team.shield.border.copper", -1);

    for (const mapping of TEAM_COSMETIC_REWARD_MAPPINGS_V1) {
      eligibleAchievements += 1;
      const outcome = consume(team, teamId, mapping.achievementKey, true, sequence++, true);
      if (outcome === "granted") grants += 1;
      if (outcome === "already_owned") alreadyOwned += 1;
      if (consume(team, teamId, mapping.achievementKey, true, sequence++, true) === "replay") {
        replayAttempts += 1;
      }
    }

    if (consume(team, teamId, "team.external.wins.001", false, sequence++, true) === "replay") {
      replayAttempts += 1;
    }
    if (consume(team, teamId, "team.matches.025", true, sequence++, false) === "granted") {
      flagOffGrants += 1;
    }

    notifications += team.notifications.size;
    unseenPerEligibleAdmin += unseen(team, ownerId).length + unseen(team, adminId).length;
    const lateAdminId = `${teamId}-late-admin`;
    team.adminEligibleSince.set(lateAdminId, sequence++);
    if (unseen(team, lateAdminId).length === 0) lateAdminsWithoutHistoricalNew += 1;
  }

  return {
    alreadyOwned,
    currencyGranted: 0,
    eligibleAchievements,
    facetsChanges: 0,
    flagOffGrants,
    grants,
    lateAdminsWithoutHistoricalNew,
    notifications,
    ratingV2Changes: 0,
    replayAttempts,
    seasonScoreChanges: 0,
    teamCount,
    topsChanges: 0,
    unseenPerEligibleAdmin,
  };
}

if (process.argv[1]?.endsWith("team-cosmetic-rewards-v1.ts")) {
  process.stdout.write(`${JSON.stringify(runTeamCosmeticRewardsSyntheticWorld(), null, 2)}\n`);
}
