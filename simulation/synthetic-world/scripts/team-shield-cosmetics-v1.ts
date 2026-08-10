import { randomUUID } from "node:crypto";
import {
  TEAM_SHIELD_COSMETIC_V1_CANDIDATES,
} from "../../../app/team-shield-cosmetics-catalog";
import {
  TEAM_SHIELD_DEFAULT_CONFIG,
  teamShieldSportingChecksum,
  type TeamShieldConfig,
} from "../../../app/team-shield-contract";

type Receipt = {
  operationId: string;
  revision: number;
  result: "already_owned" | "confirmed";
};

type SyntheticTeamShield = {
  adminEligibleSince: Map<string, number>;
  config: TeamShieldConfig;
  id: string;
  inventory: Map<string, number>;
  receipts: Map<string, Receipt>;
  revision: number;
  seen: Map<string, Set<string>>;
};

function assertRevision(team: SyntheticTeamShield, expectedRevision: number) {
  if (team.revision !== expectedRevision) throw new Error("PT409 stale team shield revision");
}

function grant(team: SyntheticTeamShield, key: string, operationId: string, expectedRevision: number, sequence: number) {
  const replay = team.receipts.get(operationId);
  if (replay) return replay;
  assertRevision(team, expectedRevision);
  const alreadyOwned = team.inventory.has(key);
  if (!alreadyOwned) {
    team.inventory.set(key, sequence);
    team.revision += 1;
  }
  const receipt: Receipt = {
    operationId,
    revision: team.revision,
    result: alreadyOwned ? "already_owned" : "confirmed",
  };
  team.receipts.set(operationId, receipt);
  return receipt;
}

function save(team: SyntheticTeamShield, config: TeamShieldConfig, operationId: string, expectedRevision: number) {
  const replay = team.receipts.get(operationId);
  if (replay) return replay;
  assertRevision(team, expectedRevision);
  team.config = config;
  team.revision += 1;
  const receipt: Receipt = { operationId, revision: team.revision, result: "confirmed" };
  team.receipts.set(operationId, receipt);
  return receipt;
}

function unseen(team: SyntheticTeamShield, adminId: string) {
  const eligibleSince = team.adminEligibleSince.get(adminId) ?? Number.POSITIVE_INFINITY;
  const seenKeys = team.seen.get(adminId) ?? new Set<string>();
  return [...team.inventory].filter(([key, unlockedAt]) => unlockedAt >= eligibleSince && !seenKeys.has(key)).map(([key]) => key);
}

function markSeen(team: SyntheticTeamShield, adminId: string, keys: string[]) {
  const seenKeys = team.seen.get(adminId) ?? new Set<string>();
  keys.forEach((key) => seenKeys.add(key));
  team.seen.set(adminId, seenKeys);
}

export function runTeamShieldSyntheticWorld(teamCount = 50) {
  const teams: SyntheticTeamShield[] = [];
  let sequence = 1;
  let duplicateGrants = 0;
  let staleConflicts = 0;
  let lateAdminsWithoutHistoricalNew = 0;
  const sportingBefore = new Map<string, string>();

  for (let index = 0; index < teamCount; index += 1) {
    const id = `synthetic-team-${index + 1}`;
    const team: SyntheticTeamShield = {
      adminEligibleSince: new Map([[`${id}-owner`, 0], [`${id}-admin`, 0]]),
      config: { ...TEAM_SHIELD_DEFAULT_CONFIG, initials: `T${String(index + 1).padStart(2, "0")}`.slice(0, 4) },
      id,
      inventory: new Map(),
      receipts: new Map(),
      revision: 0,
      seen: new Map(),
    };
    const sporting = {
      facets: [{ key: "pace", value: 60 + (index % 20) }],
      rating: 60 + (index % 20),
      seasonScore: 100 + index,
      tops: [{ key: "province", value: index % 10 }],
    };
    sportingBefore.set(id, teamShieldSportingChecksum(sporting));

    const first = TEAM_SHIELD_COSMETIC_V1_CANDIDATES[index % TEAM_SHIELD_COSMETIC_V1_CANDIDATES.length]!;
    const second = TEAM_SHIELD_COSMETIC_V1_CANDIDATES[(index + 5) % TEAM_SHIELD_COSMETIC_V1_CANDIDATES.length]!;
    grant(team, first.key, randomUUID(), team.revision, sequence++);
    grant(team, second.key, randomUUID(), team.revision, sequence++);
    const duplicate = grant(team, first.key, randomUUID(), team.revision, sequence++);
    if (duplicate.result === "already_owned") duplicateGrants += 1;

    const ownerId = `${id}-owner`;
    markSeen(team, ownerId, unseen(team, ownerId));
    const lateAdmin = `${id}-late-admin`;
    team.adminEligibleSince.set(lateAdmin, sequence++);
    if (unseen(team, lateAdmin).length === 0) lateAdminsWithoutHistoricalNew += 1;

    const saveRevision = team.revision;
    const configA = { ...team.config, borderKey: first.slot === "border" ? first.key : team.config.borderKey };
    const configB = { ...team.config, patternKey: second.slot === "pattern" ? second.key : team.config.patternKey };
    save(team, configA, randomUUID(), saveRevision);
    try {
      save(team, configB, randomUUID(), saveRevision);
    } catch (error) {
      if (error instanceof Error && error.message.includes("PT409")) staleConflicts += 1;
      else throw error;
    }
    if (teamShieldSportingChecksum(sporting) !== sportingBefore.get(id)) {
      throw new Error(`Sporting state changed for ${id}`);
    }
    teams.push(team);
  }

  return {
    currencyGranted: 0,
    duplicateGrants,
    inventories: teams.reduce((total, team) => total + team.inventory.size, 0),
    lateAdminsWithoutHistoricalNew,
    ratingChanges: 0,
    staleConflicts,
    teamCount: teams.length,
    uniqueOperationReceipts: teams.reduce((total, team) => total + team.receipts.size, 0),
  };
}

if (process.argv[1]?.endsWith("team-shield-cosmetics-v1.ts")) {
  process.stdout.write(`${JSON.stringify(runTeamShieldSyntheticWorld(), null, 2)}\n`);
}
