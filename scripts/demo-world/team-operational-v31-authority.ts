import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

export const TEAM_OPERATIONAL_V31_AUTHORITY_PROOF_VERSION = 1 as const;

export const TEAM_OPERATIONAL_V31_SCENARIO_IDS = [
  "TEAM_A_ACTIVE",
  "TEAM_B_UNDER_REVIEW",
  "TEAM_C_LIMITED_SOCIAL_ONLY",
  "TEAM_D_SUSPENDED_NEW_ACTIVITY",
  "TEAM_E_ARCHIVED",
  "TEAM_F_OWNER_TRANSFER",
  "TEAM_G_BILLING_INACTIVE",
] as const;

export type TeamOperationalV31ScenarioId = (typeof TEAM_OPERATIONAL_V31_SCENARIO_IDS)[number];

export type TeamOperationalV31Scenario = {
  allowedScopes: string[];
  billingChangedOperationalState: false;
  billingState: "INACTIVE" | "INDEPENDENT";
  blockedScopes: string[];
  challengesAllowed: boolean;
  continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH" | "HISTORY_ONLY";
  directoryVisible: boolean;
  effectiveStatus: "ACTIVE" | "ARCHIVED" | "LIMITED" | "SUSPENDED" | "UNDER_REVIEW";
  enforcement: "CLEAR" | "LIMITED" | "SUSPENDED" | "UNDER_REVIEW";
  existingCompetitionOperationsAllowed: boolean;
  id: TeamOperationalV31ScenarioId;
  lifecycle: "ACTIVE" | "ARCHIVED";
  marketplaceAllowed: boolean;
  newCompetitionOrganizerAllowed: boolean;
  newCompetitionRegistrationAllowed: boolean;
  newMatchAllowed: boolean;
  newOwnerAppealStatus: "SUBMITTED" | null;
  ownerTransferred: boolean;
  restrictionPreset: "CUSTOM" | "NEW_ACTIVITY_ONLY" | "SOCIAL_ONLY";
  reviewOpen: boolean;
  reviewPubliclyVisible: false;
  revision: number;
  sportingHistoryPreserved: true;
  teamName: string;
};

export type TeamOperationalV31AuthorityProof = {
  authorityHash: string;
  competitionContinuity: {
    sourceAuthorityHash: string;
    teamC: {
      canonicalResult: { away: number; home: number };
      existingCompetitionOperationsAllowed: true;
      officialResultProvenance: "demo-world-canonical-league-engine";
      pointsAfter: number;
      pointsBefore: number;
      restrictionPreset: "SOCIAL_ONLY";
      standingsChangedByOfficialResult: true;
    };
    teamD: {
      automaticForfeitCreated: false;
      automaticNoShowCreated: false;
      historicalResultPreserved: true;
      newCompetitionRegistrationBlocked: true;
    };
  };
  database: "temporary-local-postgresql";
  generatedAt: "2026-08-30T12:00:00.000Z";
  operationReceipts: number;
  ownershipTransferReceipts: 1;
  preservation: {
    automaticForfeitsCreated: 0;
    automaticNoShowsCreated: 0;
    officialResultsUnchanged: true;
    playerCosmeticsUnchanged: true;
    ratingSnapshotsUnchanged: true;
    rewardGrantsUnchanged: true;
    standingsRewrittenByRestriction: false;
    teamCosmeticsUnchanged: true;
  };
  privacy: {
    containsAuthUuid: false;
    containsBillingId: false;
    containsEmail: false;
    containsPhone: false;
    containsPrivateEvidence: false;
    containsPrivateMessage: false;
    containsReviewerIdentity: false;
  };
  remoteWrites: 0;
  rpcFamilies: ["TEAM_OPERATIONAL_STATE", "TEAM_OWNERSHIP_TRANSFER"];
  scenarios: TeamOperationalV31Scenario[];
  serverSequenceOrdered: true;
  settingsRevision: 2;
  source: "simulation-world";
  version: typeof TEAM_OPERATIONAL_V31_AUTHORITY_PROOF_VERSION;
};

export function teamOperationalV31AuthorityHash(
  proof: Omit<TeamOperationalV31AuthorityProof, "authorityHash">,
) {
  return createHash("sha256").update(JSON.stringify(proof)).digest("hex");
}

export function assertTeamOperationalV31AuthorityProof(value: TeamOperationalV31AuthorityProof) {
  if (value.version !== TEAM_OPERATIONAL_V31_AUTHORITY_PROOF_VERSION
      || value.database !== "temporary-local-postgresql"
      || value.source !== "simulation-world"
      || value.remoteWrites !== 0
      || value.settingsRevision !== 2
      || value.operationReceipts !== 7
      || value.ownershipTransferReceipts !== 1
      || !value.serverSequenceOrdered) {
    throw new Error("TEAM_OPERATIONAL_V31_AUTHORITY_HEADER_INVALID");
  }
  if (value.rpcFamilies.join(",") !== "TEAM_OPERATIONAL_STATE,TEAM_OWNERSHIP_TRANSFER") {
    throw new Error("TEAM_OPERATIONAL_V31_RPC_FAMILIES_INVALID");
  }
  if (value.scenarios.map(({ id }) => id).join(",") !== TEAM_OPERATIONAL_V31_SCENARIO_IDS.join(",")) {
    throw new Error("TEAM_OPERATIONAL_V31_SCENARIOS_INCOMPLETE");
  }
  const scenarios = new Map(value.scenarios.map((scenario) => [scenario.id, scenario]));
  const active = scenarios.get("TEAM_A_ACTIVE");
  const review = scenarios.get("TEAM_B_UNDER_REVIEW");
  const limited = scenarios.get("TEAM_C_LIMITED_SOCIAL_ONLY");
  const suspended = scenarios.get("TEAM_D_SUSPENDED_NEW_ACTIVITY");
  const archived = scenarios.get("TEAM_E_ARCHIVED");
  const transferred = scenarios.get("TEAM_F_OWNER_TRANSFER");
  const billing = scenarios.get("TEAM_G_BILLING_INACTIVE");
  if (active?.effectiveStatus !== "ACTIVE" || !active.marketplaceAllowed || !active.challengesAllowed
      || !active.newCompetitionRegistrationAllowed) {
    throw new Error("TEAM_OPERATIONAL_V31_ACTIVE_STORY_INVALID");
  }
  if (review?.effectiveStatus !== "UNDER_REVIEW" || !review.reviewOpen
      || review.reviewPubliclyVisible || !review.marketplaceAllowed || !review.challengesAllowed) {
    throw new Error("TEAM_OPERATIONAL_V31_REVIEW_STORY_INVALID");
  }
  if (limited?.effectiveStatus !== "LIMITED" || limited.restrictionPreset !== "SOCIAL_ONLY"
      || limited.marketplaceAllowed || limited.challengesAllowed
      || !limited.newCompetitionRegistrationAllowed || !limited.existingCompetitionOperationsAllowed) {
    throw new Error("TEAM_OPERATIONAL_V31_LIMITED_STORY_INVALID");
  }
  if (suspended?.effectiveStatus !== "SUSPENDED" || suspended.restrictionPreset !== "NEW_ACTIVITY_ONLY"
      || suspended.newCompetitionRegistrationAllowed || suspended.newCompetitionOrganizerAllowed
      || suspended.newMatchAllowed || !suspended.existingCompetitionOperationsAllowed) {
    throw new Error("TEAM_OPERATIONAL_V31_SUSPENDED_STORY_INVALID");
  }
  if (archived?.effectiveStatus !== "ARCHIVED" || archived.directoryVisible
      || archived.continuityPolicy !== "HISTORY_ONLY" || !archived.sportingHistoryPreserved) {
    throw new Error("TEAM_OPERATIONAL_V31_ARCHIVED_STORY_INVALID");
  }
  if (!transferred?.ownerTransferred || transferred.newOwnerAppealStatus !== "SUBMITTED"
      || transferred.effectiveStatus !== "LIMITED") {
    throw new Error("TEAM_OPERATIONAL_V31_OWNER_TRANSFER_STORY_INVALID");
  }
  if (billing?.billingState !== "INACTIVE" || billing.billingChangedOperationalState
      || billing.effectiveStatus !== "ACTIVE") {
    throw new Error("TEAM_OPERATIONAL_V31_BILLING_INDEPENDENCE_INVALID");
  }
  if (!value.competitionContinuity.teamC.existingCompetitionOperationsAllowed
      || !value.competitionContinuity.teamC.standingsChangedByOfficialResult
      || value.competitionContinuity.teamC.pointsAfter <= value.competitionContinuity.teamC.pointsBefore
      || !value.competitionContinuity.teamD.newCompetitionRegistrationBlocked
      || !value.competitionContinuity.teamD.historicalResultPreserved
      || value.competitionContinuity.teamD.automaticForfeitCreated
      || value.competitionContinuity.teamD.automaticNoShowCreated) {
    throw new Error("TEAM_OPERATIONAL_V31_COMPETITION_CONTINUITY_INVALID");
  }
  if (value.preservation.automaticForfeitsCreated !== 0
      || value.preservation.automaticNoShowsCreated !== 0
      || !value.preservation.officialResultsUnchanged
      || !value.preservation.ratingSnapshotsUnchanged
      || !value.preservation.rewardGrantsUnchanged
      || !value.preservation.teamCosmeticsUnchanged
      || !value.preservation.playerCosmeticsUnchanged
      || value.preservation.standingsRewrittenByRestriction) {
    throw new Error("TEAM_OPERATIONAL_V31_SPORTING_HISTORY_MUTATED");
  }
  if (Object.values(value.privacy).some(Boolean)) {
    throw new Error("TEAM_OPERATIONAL_V31_PRIVACY_DECLARATION_INVALID");
  }
  const serialized = JSON.stringify(value);
  if (/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(serialized)
      || /@(?:example|test)|\+34|"(?:privateNote|evidence|reviewer|authUserId|billingId)"\s*:|(?:cus|sub|price|prod)_[A-Za-z0-9_]+/i.test(serialized)) {
    throw new Error("TEAM_OPERATIONAL_V31_PRIVATE_DATA_LEAK");
  }
  const { authorityHash, ...payload } = value;
  if (authorityHash !== teamOperationalV31AuthorityHash(payload)) {
    throw new Error("TEAM_OPERATIONAL_V31_AUTHORITY_HASH_INVALID");
  }
  return value;
}

export function loadTeamOperationalV31AuthorityProof(
  root = path.resolve(import.meta.dirname, "../.."),
) {
  const value = JSON.parse(readFileSync(
    path.join(root, "scripts/demo-world/team-operational-v31-authority-proof.json"),
    "utf8",
  )) as TeamOperationalV31AuthorityProof;
  return assertTeamOperationalV31AuthorityProof(value);
}
