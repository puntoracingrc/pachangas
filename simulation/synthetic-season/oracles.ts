import type {
  SyntheticSeasonBracketNode,
  SyntheticSeasonCheckpoint,
  SyntheticSeasonDisciplineEvent,
  SyntheticSeasonIndex,
  SyntheticSeasonMatch,
  SyntheticSeasonMatchSheet,
  SyntheticSeasonSanction,
  SyntheticSeasonStandingRow,
} from "../../app/demo-world/demo-world-v3-2-contract";
import { syntheticSeasonHash } from "./engine";

function independentStandings(teamIds: readonly string[], matches: readonly SyntheticSeasonMatch[]): SyntheticSeasonStandingRow[] {
  const records = Object.fromEntries(teamIds.map((teamId) => [teamId, {
    draws: 0,
    goalDifference: 0,
    goalsAgainst: 0,
    goalsFor: 0,
    losses: 0,
    played: 0,
    points: 0,
    position: 0,
    teamId,
    wins: 0,
  } satisfies SyntheticSeasonStandingRow]));
  matches.forEach(({ awayTeamId, homeTeamId, result }) => {
    const home = records[homeTeamId];
    const away = records[awayTeamId];
    if (!home || !away) return;
    home.played += 1;
    away.played += 1;
    home.goalsFor += result.home;
    home.goalsAgainst += result.away;
    away.goalsFor += result.away;
    away.goalsAgainst += result.home;
    if (result.home === result.away) {
      home.draws += 1;
      away.draws += 1;
      home.points += 1;
      away.points += 1;
    } else {
      const winner = result.home > result.away ? home : away;
      const loser = winner === home ? away : home;
      winner.wins += 1;
      winner.points += 3;
      loser.losses += 1;
    }
  });
  return Object.values(records)
    .map((row) => ({ ...row, goalDifference: row.goalsFor - row.goalsAgainst }))
    .sort((a, b) => b.points - a.points || b.goalDifference - a.goalDifference || b.goalsFor - a.goalsFor || a.teamId.localeCompare(b.teamId))
    .map((row, index) => ({ ...row, position: index + 1 }));
}

function independentBracket(matches: readonly SyntheticSeasonMatch[]): SyntheticSeasonBracketNode[] {
  return matches
    .filter((match) => match.kind === "TOURNAMENT_KNOCKOUT")
    .map((match) => ({
      awayTeamId: match.awayTeamId,
      homeTeamId: match.homeTeamId,
      id: `node_${match.canonicalMatchId}`,
      matchId: match.canonicalMatchId,
      round: match.stage as SyntheticSeasonBracketNode["round"],
      winnerTeamId: match.result.winnerTeamId!,
    }));
}

export function syntheticSeasonBracketLineageErrors(matches: readonly SyntheticSeasonMatch[]) {
  const errors: string[] = [];
  const competitionIds = [...new Set(matches
    .filter(({ kind }) => kind === "TOURNAMENT_KNOCKOUT")
    .map(({ competitionId }) => competitionId)
    .filter((competitionId): competitionId is string => Boolean(competitionId)))];
  for (const competitionId of competitionIds) {
    const competitionMatches = matches.filter((match) => match.competitionId === competitionId && match.kind === "TOURNAMENT_KNOCKOUT");
    const quarters = competitionMatches.filter(({ stage }) => stage === "QUARTERFINAL");
    const semifinals = competitionMatches.filter(({ stage }) => stage === "SEMIFINAL");
    const finals = competitionMatches.filter(({ stage }) => stage === "FINAL");
    const thirdPlaces = competitionMatches.filter(({ stage }) => stage === "THIRD_PLACE");
    if (quarters.length !== 4 || semifinals.length !== 2 || finals.length !== 1) {
      errors.push(`BRACKET_TOPOLOGY_INVALID:${competitionId}`);
      continue;
    }
    const quarterWinners = quarters.map(({ result }) => result.winnerTeamId);
    const semifinalEntrants = semifinals.flatMap(({ awayTeamId, homeTeamId }) => [homeTeamId, awayTeamId]);
    if ([...quarterWinners].sort().join("|") !== [...semifinalEntrants].sort().join("|")) {
      errors.push(`BRACKET_QUARTERFINAL_LINEAGE_DIVERGED:${competitionId}`);
    }
    const semifinalWinners = semifinals.map(({ result }) => result.winnerTeamId).sort();
    const finalEntrants = [finals[0]!.homeTeamId, finals[0]!.awayTeamId].sort();
    if (semifinalWinners.join("|") !== finalEntrants.join("|")) {
      errors.push(`BRACKET_SEMIFINAL_LINEAGE_DIVERGED:${competitionId}`);
    }
    if (!finals[0]!.result.winnerTeamId || !finalEntrants.includes(finals[0]!.result.winnerTeamId!)) {
      errors.push(`BRACKET_CHAMPION_INVALID:${competitionId}`);
    }
    if (thirdPlaces.length === 1) {
      const semifinalLosers = semifinals.map((match) => match.result.winnerTeamId === match.homeTeamId ? match.awayTeamId : match.homeTeamId).sort();
      const thirdPlaceEntrants = [thirdPlaces[0]!.homeTeamId, thirdPlaces[0]!.awayTeamId].sort();
      if (semifinalLosers.join("|") !== thirdPlaceEntrants.join("|")) {
        errors.push(`BRACKET_THIRD_PLACE_LINEAGE_DIVERGED:${competitionId}`);
      }
    } else if (thirdPlaces.length > 1) {
      errors.push(`BRACKET_THIRD_PLACE_TOPOLOGY_INVALID:${competitionId}`);
    }
  }
  return errors;
}

export function syntheticSeasonMatchSheetErrors(
  index: Pick<SyntheticSeasonIndex, "matchSheets" | "matches" | "players">,
  sanctions: readonly SyntheticSeasonSanction[],
) {
  const errors: string[] = [];
  for (const match of index.matches) {
    const sheets = index.matchSheets.filter(({ canonicalMatchId }) => canonicalMatchId === match.canonicalMatchId);
    if (sheets.length !== 2) errors.push(`MATCH_SHEET_COUNT_INVALID:${match.canonicalMatchId}`);
    if (new Set(sheets.map(({ teamId }) => teamId)).size !== sheets.length) errors.push(`MATCH_SHEET_DUPLICATE_TEAM:${match.canonicalMatchId}`);
    const noShowCount = sheets.filter(({ attendance }) => attendance === "NO_SHOW").length;
    if (noShowCount !== (match.anomaly === "NO_SHOW" ? 1 : 0)) errors.push(`MATCH_SHEET_NO_SHOW_DIVERGED:${match.canonicalMatchId}`);
  }
  for (const sheet of index.matchSheets) {
    const match = index.matches.find(({ canonicalMatchId }) => canonicalMatchId === sheet.canonicalMatchId);
    if (!match) {
      errors.push(`MATCH_SHEET_UNKNOWN_MATCH:${sheet.id}`);
      continue;
    }
    const selected = [...sheet.starterPlayerIds, ...sheet.substitutePlayerIds];
    if (new Set(selected).size !== selected.length) errors.push(`MATCH_SHEET_DUPLICATE_PLAYER:${sheet.id}`);
    if (selected.some((playerId) => !index.players.some(({ id, teamId }) => id === playerId && teamId === sheet.teamId))) errors.push(`MATCH_SHEET_FOREIGN_PLAYER:${sheet.id}`);
    const activeSanctioned = sanctions.filter(({ fulfilledAtWeek, imposedAtWeek, playerId }) => (
      imposedAtWeek < match.week && fulfilledAtWeek >= match.week && index.players.some(({ id, teamId }) => id === playerId && teamId === sheet.teamId)
    )).map(({ playerId }) => playerId);
    if (selected.some((playerId) => activeSanctioned.includes(playerId))) errors.push(`MATCH_SHEET_SANCTIONED_PLAYER:${sheet.id}`);
    if ([...sheet.sanctionedPlayerIds].sort().join("|") !== [...activeSanctioned].sort().join("|")) errors.push(`MATCH_SHEET_SANCTION_SNAPSHOT_DIVERGED:${sheet.id}`);
  }
  return errors;
}

export function syntheticSeasonOracleReport(input: {
  checkpoints: SyntheticSeasonCheckpoint[];
  disciplineEvents: SyntheticSeasonDisciplineEvent[];
  index: SyntheticSeasonIndex;
  sanctions: SyntheticSeasonSanction[];
}) {
  const finalCheckpoint = input.checkpoints.at(-1)!;
  const standings = Object.fromEntries(input.index.competitions.map((competition) => [
    competition.id,
    independentStandings(
      competition.teamIds,
      input.index.matches.filter(({ competitionId, kind }) => competitionId === competition.id
        && (kind === "LEAGUE" || kind === "TOURNAMENT_GROUP")),
    ),
  ]));
  const bracket = independentBracket(input.index.matches);
  const assignmentCounts = Object.fromEntries(input.index.referees.map(({ id }) => [
    id,
    input.index.matches.filter(({ refereeId }) => refereeId === id).length,
  ]));
  const refereeProjection = input.index.referees.map((referee) => ({ ...referee, assignmentCount: assignmentCounts[referee.id] ?? 0 }));
  const squadProjection: SyntheticSeasonMatchSheet[] = input.index.matchSheets;
  const operationalState = input.index.teams;
  const discipline = { events: input.disciplineEvents, sanctions: input.sanctions };
  const errors: string[] = [];

  if (JSON.stringify(standings) !== JSON.stringify(finalCheckpoint.standings)) errors.push("STANDINGS_ORACLE_DIVERGED");
  if (JSON.stringify(bracket) !== JSON.stringify(finalCheckpoint.bracket)) errors.push("BRACKET_ORACLE_DIVERGED");
  if (syntheticSeasonHash(standings) !== input.index.proof.oracleHashes.standings) errors.push("STANDINGS_HASH_DIVERGED");
  if (syntheticSeasonHash(bracket) !== input.index.proof.oracleHashes.bracket) errors.push("BRACKET_HASH_DIVERGED");
  if (syntheticSeasonHash(discipline) !== input.index.proof.oracleHashes.discipline) errors.push("DISCIPLINE_HASH_DIVERGED");
  if (syntheticSeasonHash(refereeProjection) !== input.index.proof.oracleHashes.referee) errors.push("REFEREE_HASH_DIVERGED");
  if (syntheticSeasonHash(operationalState) !== input.index.proof.oracleHashes.operationalState) errors.push("OPERATIONAL_STATE_HASH_DIVERGED");
  errors.push(...syntheticSeasonBracketLineageErrors(input.index.matches));
  errors.push(...syntheticSeasonMatchSheetErrors(input.index, input.sanctions));

  for (const event of input.disciplineEvents) {
    const match = input.index.matches.find(({ canonicalMatchId }) => canonicalMatchId === event.canonicalMatchId);
    if (!match) errors.push(`DISCIPLINE_UNKNOWN_MATCH:${event.id}`);
    if (match?.refereeId && (event.refereeAssignmentId !== match.refereeAssignmentId || event.reportingRefereeId !== match.refereeId)) {
      errors.push(`DISCIPLINE_REFEREE_LINEAGE_DIVERGED:${event.id}`);
    }
  }
  for (const sanction of input.sanctions) {
    if (sanction.fulfilledAtWeek <= sanction.imposedAtWeek) errors.push(`SANCTION_TIMELINE_INVALID:${sanction.id}`);
  }
  for (const team of input.index.teams) {
    if (team.restrictionPreset === "SOCIAL_ONLY" && (team.marketplaceAllowed || team.challengesAllowed)) errors.push(`SOCIAL_SCOPE_DIVERGED:${team.id}`);
    if (!team.competitionContinuity) errors.push(`COMPETITION_CONTINUITY_DIVERGED:${team.id}`);
    if (team.billingState === "INACTIVE" && team.state !== "ACTIVE") errors.push(`BILLING_CHANGED_OPERATIONAL_STATE:${team.id}`);
  }
  for (const competition of input.index.competitions.filter(({ kind, status }) => kind === "TOURNAMENT" && status === "COMPLETED")) {
    const finals = input.index.matches.filter(({ competitionId, stage }) => competitionId === competition.id && stage === "FINAL");
    if (finals.length !== 1 || !finals[0]?.result.winnerTeamId) errors.push(`TOURNAMENT_CHAMPION_INVALID:${competition.id}`);
  }

  return {
    errors,
    hashes: {
      bracket: syntheticSeasonHash(bracket),
      discipline: syntheticSeasonHash(discipline),
      operationalState: syntheticSeasonHash(operationalState),
      referee: syntheticSeasonHash(refereeProjection),
      squads: syntheticSeasonHash(squadProjection),
      standings: syntheticSeasonHash(standings),
    },
    passed: errors.length === 0,
  };
}
