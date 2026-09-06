export type TeamRankingSort = "media" | "goles" | "partidos" | "ganados";
export const rankingSortLabels: Record<TeamRankingSort, string> = { media: "Media", goles: "Goles", partidos: "Partidos", ganados: "Ganados" };
type Row = Record<string, unknown>;
const record = (value: unknown): Row => value && typeof value === "object" && !Array.isArray(value) ? value as Row : {};
const rows = (value: unknown): Row[] => Array.isArray(value) ? value.map(record) : [];
const text = (value: unknown) => typeof value === "string" ? value : "";
const number = (value: unknown, fallback = 0) => value !== null && value !== "" && Number.isFinite(Number(value)) ? Number(value) : fallback;
const clamp = (value: unknown) => Math.max(1, Math.min(10, number(value, 5)));
const average = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length;
const facetKeys = ["ritmo", "tiro", "pase", "regate", "defensa", "fisico"];
const positionShort: Record<string, string> = { Portero: "POR", "Defensa central": "DFC", "Lateral derecho": "LD", "Lateral izquierdo": "LI", Carrilero: "CAR", "Pivote defensivo": "MCD", "Mediocentro / pivote": "PIV", "Interior / volante": "INT", Mediapunta: "MP", "Extremo derecho": "ED", "Extremo izquierdo": "EI", "Delantero centro": "DC", "Segundo delantero": "SD", "Delantero / punta": "DEL", Cierre: "CIE", "Ala derecha": "ALD", "Ala izquierda": "ALI", Pívot: "PIV" };

export function rankingSeason(date: string | Date) {
  const parsed = new Date(date);
  if (!Number.isFinite(parsed.getTime())) return "Sin temporada";
  const year = parsed.getFullYear() - (parsed.getMonth() < 8 ? 1 : 0);
  return `${year}-${year + 1}`;
}
const seasonOf = (match: Row) => text(match.season) || rankingSeason(text(match.date));
export function teamRankingSeasons(payload: unknown, now = new Date()) {
  return [...new Set([rankingSeason(now), ...rows(record(payload).matches).map(seasonOf)])].sort((a, b) => b.localeCompare(a));
}

// Preserve the group card's role-specific, bounded peer ratings (1–10).
function playerFacets(player: Row, goalkeeper: boolean) {
  const legacy = Array.isArray(player.ratings) ? player.ratings.map(clamp) : [];
  const base = legacy.length ? average(legacy) : clamp(player.rating);
  const allVotes = rows(player.ratingVotes);
  const roleVotes = allVotes.filter(vote => vote.ratingRole === (goalkeeper ? "goalkeeper" : "field"));
  const votes = (roleVotes.length ? roleVotes : allVotes.filter(vote => !vote.ratingRole))
    .sort((a, b) => number(a.matchCount) - number(b.matchCount) || text(a.createdAt).localeCompare(text(b.createdAt)));
  return facetKeys.map(key => {
    const scores: number[] = [];
    let baseline = base;
    for (const vote of votes) {
      const value = record(vote.facets)[key] ?? baseline;
      scores.push(Math.max(clamp(baseline - 1), Math.min(clamp(baseline + 1), clamp(value))));
      baseline = average(scores);
    }
    return scores.length ? average(scores) : base;
  });
}

export function buildTeamRanking(payload: unknown, season: string, sort: TeamRankingSort) {
  const data = record(payload);
  const stats = new Map(rows(data.players).filter(player => text(player.id)).map(player => {
    const goalkeeper = player.goalkeeperOnly === true || ["Portero", "Porteria"].includes(text(player.position));
    const values = playerFacets(player, goalkeeper);
    const labels = goalkeeper ? ["SAL", "PAR", "SAQ", "REF", "VEL", "POS"] : ["RIT", "TIR", "PAS", "REG", "DEF", "FÍS"];
    const id = text(player.id);
    return [id, { id, name: text(player.name) || "Jugador", avatar: text(player.avatar),
      avatarX: number(player.avatarOffsetX, 50), avatarY: number(player.avatarOffsetY),
      position: goalkeeper ? "POR" : positionShort[text(player.position)] || "JUG",
      media: average(values) * 10, facets: values.map((value, index) => ({ key: facetKeys[index], label: labels[index], value: Math.round(value * 10) })),
      inactive: player.inactive === true, injured: player.injured === true, appearances: 0, goals: 0, wins: 0 }];
  }));
  for (const match of rows(data.matches)) {
    if (typeof match.scoreA !== "number" || typeof match.scoreB !== "number" || seasonOf(match) !== season) continue;
    const played = rows(match.players).map((entry, index) => ({ entry, index }))
      .filter(({ entry }) => entry.status === "voy")
      .sort((a, b) => (Date.parse(text(a.entry.joinedAt)) || a.index) - (Date.parse(text(b.entry.joinedAt)) || b.index))
      .slice(0, Math.max(0, number(match.targetPlayers, 14)));
    const winner = match.scoreA === match.scoreB ? [] : match.scoreA > match.scoreB ? match.teamA : match.teamB;
    const winningIds = new Set(Array.isArray(winner) ? winner : []);
    for (const id of new Set(played.map(({ entry }) => text(entry.playerId)))) {
      const player = stats.get(id);
      if (player) { player.appearances++; if (winningIds.has(id)) player.wins++; }
    }
    for (const goal of rows(match.scorers)) {
      const player = stats.get(text(goal.playerId));
      if (player) player.goals += Math.max(0, number(goal.goals));
    }
  }
  const metric = { media: "media", goles: "goals", partidos: "appearances", ganados: "wins" } as const;
  return [...stats.values()].sort((a, b) => b[metric[sort]] - a[metric[sort]] || b.media - a.media || b.goals - a.goals || b.wins - a.wins || b.appearances - a.appearances || a.name.localeCompare(b.name, "es"));
}
