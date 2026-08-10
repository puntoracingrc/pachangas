import type { EvidenceStrategy, TrophyRule } from "../../season-ranking-lab/src/integrity-v3";
import { cloneSyntheticWorldFromCurrent } from "./engine";
import { calculateRankings, SYNTHETIC_PROVINCE_TROPHY_RULE } from "./ranking";
import { deterministicUuid } from "./random";
import type { SyntheticChallenge, SyntheticMatch, SyntheticWorld } from "./types";

export type RankingCounterfactualId = "A" | "B" | "C" | "D" | "E";

const SCENARIOS: Record<RankingCounterfactualId, {
  label: string;
  mutation: NonNullable<SyntheticWorld["config"]["rankingAuditScenario"]>["mutation"];
  seed: number;
  strategy: EvidenceStrategy;
  trophyRule: TrophyRule;
}> = {
  A: { label: "V3 intacta", mutation: "none", seed: 20261101, strategy: "exclusion_and_hold", trophyRule: SYNTHETIC_PROVINCE_TROPHY_RULE },
  B: { label: "Certificación provincial 20/8", mutation: "none", seed: 20261102, strategy: "exclusion_and_hold", trophyRule: { ...SYNTHETIC_PROVINCE_TROPHY_RULE, id: "province-20/8-counterfactual", minimumChallenges: 20, minimumLogicalOpponents: 8 } },
  C: { label: "V3 + densidad de Retos 25%", mutation: "challenge_density_plus_25", seed: 20261103, strategy: "exclusion_and_hold", trophyRule: SYNTHETIC_PROVINCE_TROPHY_RULE },
  D: { label: "Rotación: no aplicada, problema no demostrado", mutation: "rotation_not_applied", seed: 20261104, strategy: "exclusion_and_hold", trophyRule: SYNTHETIC_PROVINCE_TROPHY_RULE },
  E: { label: "V3 sin holds de integridad", mutation: "none", seed: 20261105, strategy: "evidence_exclusion", trophyRule: SYNTHETIC_PROVINCE_TROPHY_RULE },
};

function counterfactualDate(world: SyntheticWorld, index: number) {
  const start = Date.parse(world.startDate);
  const end = Date.parse(world.config.seasonEnd);
  const availableDays = Math.max(1, Math.floor((end - start) / 86_400_000));
  const day = (index * 37 + 11) % availableDays;
  return new Date(start + day * 86_400_000 + (18 + index % 4) * 3_600_000).toISOString();
}

function addChallengeDensity(world: SyntheticWorld) {
  const sourceMatches = world.state.matches.filter((match) => (
    match.kind === "challenge"
      && (match.state === "confirmed" || match.state === "auto_confirmed")
      && match.awayTeamId
      && match.homeGoals !== null
      && match.awayGoals !== null
  ));
  const count = Math.round(sourceMatches.length * 0.25);
  for (let index = 0; index < count; index += 1) {
    const source = sourceMatches[(index * 53 + 17) % sourceMatches.length]!;
    const occurredAt = counterfactualDate(world, index);
    const matchId = deterministicUuid(`${world.id}:ranking-density-match`, index);
    const challengeId = deterministicUuid(`${world.id}:ranking-density-challenge`, index);
    const challenge: SyntheticChallenge = {
      awayTeamId: source.awayTeamId!,
      createdAt: occurredAt,
      homeTeamId: source.homeTeamId,
      id: challengeId,
      operationId: deterministicUuid(`${world.id}:ranking-density-create`, index),
      productChallengeId: null,
      proposedAt: occurredAt,
      state: "accepted",
    };
    const match: SyntheticMatch = {
      ...structuredClone(source),
      id: matchId,
      occurredAt,
      productMatchId: null,
    };
    world.state.challenges.push(challenge);
    world.state.matches.push(match);
    for (const agentId of match.participantIds) {
      const agent = world.state.agents.find(({ id }) => id === agentId);
      const belongsAway = Boolean(match.awayTeamId && agent?.teamIds.includes(match.awayTeamId));
      const belongsHome = Boolean(agent?.teamIds.includes(match.homeTeamId));
      world.state.attendanceRecords.push({
        agentId,
        canonicalNoShowDistinguishable: true,
        changedAt: occurredAt,
        finalOutcome: "played",
        id: deterministicUuid(`${world.id}:ranking-density-attendance`, `${matchId}:${agentId}`),
        initialStatus: "voy",
        matchId,
        teamId: belongsAway && !belongsHome ? match.awayTeamId! : match.homeTeamId,
      });
    }
  }
  return count;
}

export function rankingAuditOptionsForWorld(world: SyntheticWorld) {
  const scenario = world.config.rankingAuditScenario;
  if (!scenario) return {};
  return {
    strategy: scenario.strategy,
    trophyRule: {
      ...SYNTHETIC_PROVINCE_TROPHY_RULE,
      id: `province-${scenario.trophyMinimumChallenges}/${scenario.trophyMinimumLogicalOpponents}-counterfactual-${scenario.id}`,
      minimumChallenges: scenario.trophyMinimumChallenges,
      minimumLogicalOpponents: scenario.trophyMinimumLogicalOpponents,
    },
  };
}

export function createRankingCounterfactualClone(source: SyntheticWorld, id: RankingCounterfactualId) {
  const scenario = SCENARIOS[id];
  const clone = cloneSyntheticWorldFromCurrent(source, scenario.seed, `${source.name} · Clone ${id} · ${scenario.label}`);
  clone.config.rankingAuditScenario = {
    id,
    mutation: scenario.mutation,
    sourceWorldId: source.id,
    strategy: scenario.strategy as "evidence_exclusion" | "exclusion_and_hold",
    trophyMinimumChallenges: scenario.trophyRule.minimumChallenges,
    trophyMinimumLogicalOpponents: scenario.trophyRule.minimumLogicalOpponents,
  };
  const addedMatches = scenario.mutation === "challenge_density_plus_25" ? addChallengeDensity(clone) : 0;
  clone.state.eventSequence += 1;
  clone.state.events.push({
    actorAgentId: null,
    entityIds: [source.id, clone.id],
    eventType: "ranking_counterfactual_created",
    expected: { sourceRevision: source.revision },
    flow: "ranking.counterfactual",
    operationId: deterministicUuid(`${clone.id}:ranking-counterfactual`, id),
    payload: {
      addedMatches,
      formulasChanged: id === "B",
      mutation: scenario.mutation,
      scenario: id,
      sourceWorldId: source.id,
      sourceWorldRevision: source.revision,
      strategy: scenario.strategy,
      trophyRule: scenario.trophyRule,
    },
    sequence: clone.state.eventSequence,
    status: "pass",
    virtualDate: clone.currentDate,
  });
  clone.state.rankings = calculateRankings(clone, { strategy: scenario.strategy, trophyRule: scenario.trophyRule });
  return { addedMatches, clone, scenario };
}

export function rankingCounterfactualScenario(id: RankingCounterfactualId) {
  return SCENARIOS[id];
}
