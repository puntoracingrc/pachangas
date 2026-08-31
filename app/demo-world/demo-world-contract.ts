import type { AttributeRatings } from "../laboratorio-ficha-jugador/_engine/player-rating-engine";
import type { PlayerCosmeticLoadout, PlayerCosmeticRarity } from "../player-cosmetics-contract";
import type { ProvincialOwnRank, ProvincialRankingPayload } from "../ranking/provincial-ranking-contract";
import type { TeamShieldConfig } from "../team-shield-contract";

export const DEMO_WORLD_VERSION = 1 as const;
export const DEMO_WORLD_SEASON = "2026/27" as const;
export const DEMO_WORLD_MODE = "demo-world-read-only" as const;

export type DemoWorldPerspectiveId = "admin" | "club-organizer" | "free-agent" | "league-organizer" | "platform-reviewer"
  | "player" | "referee" | "team-owner" | "tournament-organizer";
export type DemoWorldPrimaryTab = "inicio" | "partido" | "retos" | "mercado" | "equipo" | "perfil";
export type DemoMatchKind = "sala" | "futbol7" | "futbol11";
export type DemoMatchScope = "challenge" | "internal";
export type DemoMatchStatus = "finalized" | "scheduled";
export type DemoWorldAttendanceStatus = "excused_absence" | "late_cancellation" | "played" | "unexcused_no_show";
export type DemoWorldMatchPane = "admin" | "alineacion" | "historico" | "proximo" | "resultado";
export type DemoWorldRankingShowcaseId = "ineligible" | "my-rank" | "pending-review" | "provisional";

export type DemoWorldManifest = {
  chunks: {
    activity: string;
    core: string;
    matches: string;
    players: string;
  };
  counts: {
    achievements: number;
    challenges: number;
    matches: number;
    notifications: number;
    players: number;
    rewardBoxes: number;
    stories: number;
    teams: number;
  };
  demoNow: string;
  generatedAt: string;
  hash: string;
  mode: typeof DEMO_WORLD_MODE;
  season: typeof DEMO_WORLD_SEASON;
  seed: string;
  version: typeof DEMO_WORLD_VERSION;
};

export type DemoWorldPerspective = {
  id: DemoWorldPerspectiveId;
  label: string;
  playerId: string;
  role: "admin" | "player" | "visitor";
  summary: string;
  teamId: string | null;
};

export type DemoWorldVenue = {
  id: string;
  kind: DemoMatchKind;
  label: string;
  publicLocation: string;
  territory: string;
};

export type DemoWorldTeamStats = {
  challengeDraws: number;
  challengeLosses: number;
  challengesPlayed: number;
  challengeWins: number;
  cleanSheets: number;
  goalsAgainst: number;
  goalsFor: number;
  matchesPlayed: number;
};

export type DemoWorldTeam = {
  foundedYear: string;
  id: string;
  identity: string;
  memberCount: number;
  name: string;
  openToChallenges: boolean;
  publicLocation: string;
  rankingLabel: string;
  shield: TeamShieldConfig;
  stats: DemoWorldTeamStats;
  territory: string;
  unlockedCosmeticKeys: string[];
};

export type DemoWorldRating = {
  currentFacets: AttributeRatings;
  currentOverall: number | null;
  domain: "field" | "goalkeeper_legacy";
  engineVersion: string;
  evaluatorCount: number;
  reliability: number;
};

export type DemoWorldPlayer = {
  appearances: number;
  assists: number;
  avatarHue: number;
  birthYear: number;
  cosmetics: PlayerCosmeticLoadout;
  featuredAchievementKey: string | null;
  goals: number;
  id: string;
  market: {
    availability: string;
    modalities: DemoMatchKind[];
    openToGuest: boolean;
    publicBio: string;
    zones: string[];
  };
  name: string;
  position: {
    abbreviation: string;
    engine: "attacking_midfielder" | "central_midfielder" | "centre_back" | "defensive_midfielder" | "full_back" | "striker" | "winger" | null;
    label: string;
  };
  rating: DemoWorldRating;
  teamId: string | null;
  wins: number;
};

export type DemoWorldScorer = {
  goals: number;
  playerId: string;
  side: "away" | "home";
};

export type DemoWorldMatch = {
  awayLabel: string;
  awayPlayerIds: string[];
  awayTeamId: string | null;
  confirmedPlayerIds: string[];
  date: string;
  homeLabel: string;
  homePlayerIds: string[];
  homeTeamId: string;
  id: string;
  kind: DemoMatchKind;
  publicOpenSlots: number;
  reservePlayerIds: string[];
  result: { away: number; home: number } | null;
  revision: number;
  scope: DemoMatchScope;
  scorers: DemoWorldScorer[];
  status: DemoMatchStatus;
  title: string;
  venueId: string;
};

export type DemoWorldChallenge = {
  awayTeamId: string;
  date: string;
  homeTeamId: string;
  id: string;
  matchId: string | null;
  message: string;
  proposedKind: DemoMatchKind;
  status: "accepted" | "cancelled" | "completed" | "countered" | "pending" | "rejected";
};

export type DemoWorldAttendanceRecord = {
  id: string;
  matchId: string;
  playerId: string;
  recordedAt: string;
  status: DemoWorldAttendanceStatus;
};

export type DemoWorldRankingRow = {
  draws: number;
  goalsAgainst: number;
  goalsFor: number;
  losses: number;
  played: number;
  points: number;
  position: number;
  teamId: string;
  wins: number;
};

export type DemoWorldAchievement = {
  description: string;
  evidence: string;
  id: string;
  key: string;
  occurredAt: string;
  rarity: PlayerCosmeticRarity;
  subjectId: string;
  subjectType: "player" | "team";
  title: string;
};

export type DemoWorldRewardBox = {
  achievementId: string;
  id: string;
  ownerId: string;
  ownerType: "player" | "team";
  rarity: PlayerCosmeticRarity;
  rewardCosmeticKey: string;
  state: "opened" | "pending";
};

export type DemoWorldNotification = {
  body: string;
  category: "achievement" | "challenge" | "group" | "market" | "match" | "security";
  createdAt: string;
  id: string;
  mandatory: boolean;
  targetId: string | null;
  targetTab: DemoWorldPrimaryTab;
  title: string;
};

export type DemoWorldStory = {
  body: string;
  date: string;
  id: string;
  referenceIds: string[];
  title: string;
  type: "achievement" | "attendance" | "challenge" | "match" | "market" | "ranking" | "reward" | "team";
};

export type DemoWorldProvincialRanking = {
  awardsEnabled: false;
  formula: {
    activityWindowWeeks: 12;
    minimumLogicalOpponents: 6;
    minimumRatingReliability: 0.45;
    minimumValidChallenges: 15;
    weights: { competition: 0.3; opposition: 0.15; quality: 0.55 };
  };
  ranking: ProvincialRankingPayload;
  showcases: Record<DemoWorldRankingShowcaseId, ProvincialOwnRank>;
};

export type DemoWorldHomePreview = {
  matches: DemoWorldMatch[];
  notifications: DemoWorldNotification[];
  players: DemoWorldPlayer[];
};

export type DemoWorldCoreChunk = {
  perspectives: DemoWorldPerspective[];
  preview: DemoWorldHomePreview;
  provincialRanking: DemoWorldProvincialRanking;
  rankings: DemoWorldRankingRow[];
  stories: DemoWorldStory[];
  teams: DemoWorldTeam[];
  venues: DemoWorldVenue[];
};

export type DemoWorldPlayersChunk = {
  players: DemoWorldPlayer[];
};

export type DemoWorldMatchesChunk = {
  attendance: DemoWorldAttendanceRecord[];
  challenges: DemoWorldChallenge[];
  matches: DemoWorldMatch[];
};

export type DemoWorldActivityChunk = {
  achievements: DemoWorldAchievement[];
  notifications: DemoWorldNotification[];
  rewardBoxes: DemoWorldRewardBox[];
  teamRewardMappings: Array<{
    achievementKey: string;
    cosmeticKey: string;
    firstOccurrenceOnly: boolean;
    label: string;
    mappingKey: string;
  }>;
};

export type DemoWorldSnapshot = {
  activity: DemoWorldActivityChunk;
  core: DemoWorldCoreChunk;
  manifest: DemoWorldManifest;
  matches: DemoWorldMatchesChunk;
  players: DemoWorldPlayersChunk;
};

export type DemoWorldSessionState = {
  attendanceByMatch: Record<string, "duda" | "no" | "voy">;
  equippedCosmeticKeys: string[];
  inventoryCosmeticKeys: string[];
  newCosmeticKeys: string[];
  openedBoxIds: string[];
  perspectiveId: DemoWorldPerspectiveId;
  readNotificationIds: string[];
};

export const DEFAULT_DEMO_WORLD_SESSION: DemoWorldSessionState = {
  attendanceByMatch: {},
  equippedCosmeticKeys: [],
  inventoryCosmeticKeys: [],
  newCosmeticKeys: [],
  openedBoxIds: [],
  perspectiveId: "player",
  readNotificationIds: [],
};

export const DEMO_WORLD_TEAM_REWARD_MAPPINGS = [
  { mappingKey: "first_challenge_win", achievementKey: "team.external.wins.001", cosmeticKey: "team.shield.border.copper", firstOccurrenceOnly: true, label: "Primera victoria" },
  { mappingKey: "ten_challenges", achievementKey: "team.external.matches.010", cosmeticKey: "team.shield.ornament.banner", firstOccurrenceOnly: false, label: "10 retos" },
  { mappingKey: "twenty_five_matches", achievementKey: "team.matches.025", cosmeticKey: "team.shield.ornament.laurels", firstOccurrenceOnly: false, label: "25 partidos" },
  { mappingKey: "fifty_matches", achievementKey: "team.matches.050", cosmeticKey: "team.shield.border.silver", firstOccurrenceOnly: false, label: "50 partidos" },
  { mappingKey: "first_clean_sheet", achievementKey: "team.external.clean_sheets.001", cosmeticKey: "team.shield.effect.edge_glow", firstOccurrenceOnly: true, label: "Primera portería a cero" },
] as const;

export const DEMO_WORLD_BLOCKED_REMOTE_OPERATIONS = [
  "fetch:POST",
  "fetch:PUT",
  "fetch:PATCH",
  "fetch:DELETE",
  "supabase:rpc",
  "supabase:insert",
  "supabase:update",
  "supabase:delete",
] as const;

export function demoWorldMatchAdminActions(status: DemoWorldMatch["status"]) {
  return status === "finalized"
    ? ["Borrar partido"]
    : ["Cerrar alineación", "Abrir al Mercado", "Invitar jugador", "Editar campo", "Crear nuevo partido", "Borrar partido"];
}

export function canDemoWorldInvite(role: DemoWorldPerspective["role"]) {
  return role === "admin";
}

export function demoWorldMatchPaneForRole(
  pane: DemoWorldMatchPane,
  role: DemoWorldPerspective["role"],
): DemoWorldMatchPane {
  return pane === "admin" && role !== "admin" ? "proximo" : pane;
}

const forbiddenKeyPatterns = [
  /(^|_)(email|phone|telephone|mobile)($|_)/i,
  /(^|_)(auth_id|auth_user_id|owner_user_id|service_role)($|_)/i,
  /(^|_)(address|private_address|medical|injury|conduct|moderation|report|receipt|token)($|_)/i,
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export function demoWorldForbiddenPaths(value: unknown, path = "snapshot"): string[] {
  if (Array.isArray(value)) {
    return value.flatMap((entry, index) => demoWorldForbiddenPaths(entry, `${path}[${index}]`));
  }
  if (!isRecord(value)) return [];

  return Object.entries(value).flatMap(([key, entry]) => {
    const nextPath = `${path}.${key}`;
    const own = forbiddenKeyPatterns.some((pattern) => pattern.test(key)) ? [nextPath] : [];
    return own.concat(demoWorldForbiddenPaths(entry, nextPath));
  });
}

export function demoWorldIntegrityErrors(snapshot: DemoWorldSnapshot): string[] {
  const errors: string[] = [];
  const teams = new Map(snapshot.core.teams.map((team) => [team.id, team]));
  const players = new Map(snapshot.players.players.map((player) => [player.id, player]));
  const matches = new Map(snapshot.matches.matches.map((match) => [match.id, match]));
  const achievements = new Map(snapshot.activity.achievements.map((achievement) => [achievement.id, achievement]));
  const attendance = new Map(snapshot.matches.attendance.map((entry) => [entry.id, entry]));

  for (const team of teams.values()) {
    if (!team.id.startsWith("demo_team_")) errors.push(`Team id is not namespaced: ${team.id}`);
    const rosterSize = snapshot.players.players.filter((player) => player.teamId === team.id).length;
    if (rosterSize !== team.memberCount) errors.push(`Roster count mismatch for ${team.id}`);
  }

  for (const player of players.values()) {
    if (!player.id.startsWith("demo_player_")) errors.push(`Player id is not namespaced: ${player.id}`);
    if (player.teamId && !teams.has(player.teamId)) errors.push(`Unknown team ${player.teamId} for ${player.id}`);
  }

  for (const match of matches.values()) {
    if (!match.id.startsWith("demo_match_")) errors.push(`Match id is not namespaced: ${match.id}`);
    if (!teams.has(match.homeTeamId)) errors.push(`Unknown home team ${match.homeTeamId} in ${match.id}`);
    if (match.awayTeamId && !teams.has(match.awayTeamId)) errors.push(`Unknown away team ${match.awayTeamId} in ${match.id}`);
    const participantIds = new Set([...match.homePlayerIds, ...match.awayPlayerIds]);
    for (const playerId of [...participantIds, ...match.confirmedPlayerIds, ...match.reservePlayerIds]) {
      if (!players.has(playerId)) errors.push(`Unknown player ${playerId} in ${match.id}`);
    }
    const homeGoals = match.scorers.filter((entry) => entry.side === "home").reduce((sum, entry) => sum + entry.goals, 0);
    const awayGoals = match.scorers.filter((entry) => entry.side === "away").reduce((sum, entry) => sum + entry.goals, 0);
    for (const scorer of match.scorers) {
      if (!participantIds.has(scorer.playerId)) errors.push(`Scorer ${scorer.playerId} did not play ${match.id}`);
    }
    if (match.result && (homeGoals !== match.result.home || awayGoals !== match.result.away)) {
      errors.push(`Scorer total mismatch in ${match.id}`);
    }
  }

  for (const challenge of snapshot.matches.challenges) {
    if (!teams.has(challenge.homeTeamId) || !teams.has(challenge.awayTeamId)) errors.push(`Unknown team in ${challenge.id}`);
    if (challenge.matchId && !matches.has(challenge.matchId)) errors.push(`Unknown match ${challenge.matchId} in ${challenge.id}`);
    const linkedMatch = challenge.matchId ? matches.get(challenge.matchId) : null;
    if ((challenge.status === "accepted" || challenge.status === "completed") && !linkedMatch) {
      errors.push(`Missing canonical match for ${challenge.status} challenge ${challenge.id}`);
    }
    if (linkedMatch && challenge.status !== "accepted" && challenge.status !== "completed") {
      errors.push(`Unconfirmed challenge ${challenge.id} links match ${linkedMatch.id}`);
    }
    if (challenge.status === "accepted" && linkedMatch?.status !== "scheduled") {
      errors.push(`Accepted challenge ${challenge.id} does not link a scheduled match`);
    }
    if (challenge.status === "completed" && linkedMatch?.status !== "finalized") {
      errors.push(`Completed challenge ${challenge.id} does not link a finalized match`);
    }
  }

  for (const record of attendance.values()) {
    const match = matches.get(record.matchId);
    if (!match || match.status !== "finalized") errors.push(`Invalid attendance match ${record.matchId} for ${record.id}`);
    if (!players.has(record.playerId)) errors.push(`Unknown attendance player ${record.playerId} for ${record.id}`);
    if (match && !match.homePlayerIds.includes(record.playerId) && !match.awayPlayerIds.includes(record.playerId) && record.status === "played") {
      errors.push(`Played attendance ${record.id} is not in the canonical lineup`);
    }
  }

  for (const achievement of achievements.values()) {
    const validSubject = achievement.subjectType === "team" ? teams.has(achievement.subjectId) : players.has(achievement.subjectId);
    if (!validSubject) errors.push(`Unknown achievement subject ${achievement.subjectId}`);
  }

  for (const box of snapshot.activity.rewardBoxes) {
    if (!achievements.has(box.achievementId)) errors.push(`Unknown achievement ${box.achievementId} for ${box.id}`);
    const validOwner = box.ownerType === "team" ? teams.has(box.ownerId) : players.has(box.ownerId);
    if (!validOwner) errors.push(`Unknown reward owner ${box.ownerId}`);
  }

  const knownReferences = new Set([
    ...teams.keys(),
    ...players.keys(),
    ...matches.keys(),
    ...snapshot.matches.challenges.map((challenge) => challenge.id),
    ...achievements.keys(),
    ...attendance.keys(),
    ...snapshot.activity.rewardBoxes.map((box) => box.id),
    ...snapshot.core.provincialRanking.ranking.items.map((entry) => entry.entryKey),
    ...Object.values(snapshot.core.provincialRanking.showcases).flatMap((entry) => entry.entryKey ? [entry.entryKey] : []),
  ]);
  for (const story of snapshot.core.stories) {
    for (const referenceId of story.referenceIds) {
      if (!knownReferences.has(referenceId)) errors.push(`Unknown story reference ${referenceId} in ${story.id}`);
    }
  }

  const forbiddenPaths = demoWorldForbiddenPaths(snapshot);
  errors.push(...forbiddenPaths.map((entry) => `Forbidden public field: ${entry}`));
  return [...new Set(errors)];
}

export function assertDemoWorldSnapshot(snapshot: DemoWorldSnapshot) {
  if (snapshot.manifest.version !== DEMO_WORLD_VERSION) throw new Error("Unsupported Demo World version");
  if (snapshot.manifest.mode !== DEMO_WORLD_MODE) throw new Error("Demo World is not read-only");
  const errors = demoWorldIntegrityErrors(snapshot);
  if (errors.length) throw new Error(`Invalid Demo World snapshot:\n${errors.join("\n")}`);
  return snapshot;
}

export function isDemoWorldRemoteWrite(input: { method?: string; operation?: string }) {
  const method = (input.method ?? "GET").toUpperCase();
  const operation = (input.operation ?? "").toLowerCase();
  return method !== "GET" || /rpc|insert|update|delete|mutat|write/.test(operation);
}

export function assertDemoWorldLocalIntent(input: { method?: string; operation?: string }) {
  if (isDemoWorldRemoteWrite(input)) {
    throw new Error("DEMO_WORLD_REMOTE_WRITE_BLOCKED");
  }
}
