import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  DEMO_WORLD_MODE,
  DEMO_WORLD_SEASON,
  DEMO_WORLD_TEAM_REWARD_MAPPINGS,
  DEMO_WORLD_VERSION,
  assertDemoWorldSnapshot,
  type DemoMatchKind,
  type DemoWorldAchievement,
  type DemoWorldActivityChunk,
  type DemoWorldAttendanceRecord,
  type DemoWorldChallenge,
  type DemoWorldCoreChunk,
  type DemoWorldManifest,
  type DemoWorldMatch,
  type DemoWorldMatchesChunk,
  type DemoWorldNotification,
  type DemoWorldPlayer,
  type DemoWorldPlayersChunk,
  type DemoWorldProvincialRanking,
  type DemoWorldRankingRow,
  type DemoWorldRewardBox,
  type DemoWorldSnapshot,
  type DemoWorldStory,
  type DemoWorldTeam,
  type DemoWorldVenue,
} from "../../app/demo-world/demo-world-contract";
import {
  ATTRIBUTE_KEYS,
  type AttributeRatings,
  type PlayerPosition,
} from "../../app/laboratorio-ficha-jugador/_engine/player-rating-engine";
import { PLAYER_COSMETIC_CATALOG } from "../../app/player-cosmetics-catalog";
import { EMPTY_PLAYER_COSMETIC_LOADOUT, type PlayerCosmeticLoadout } from "../../app/player-cosmetics-contract";
import { calculateRatingCardLayers, RATING_SYSTEM_V2_ENGINE_VERSION } from "../../app/rating-system-v2";
import { TEAM_SHIELD_RENDER_CATALOG } from "../../app/team-shield-cosmetics-catalog";
import { TEAM_SHIELD_DEFAULT_CONFIG, type TeamShieldConfig } from "../../app/team-shield-contract";

export const DEMO_WORLD_SEED = "pachangas-iq-demo-world-v1-2026-27";
export const DEMO_WORLD_NOW = "2027-03-18T18:00:00.000Z";
const DEMO_WORLD_GENERATED_AT = "2026-08-11T10:00:00.000Z";
const DEMO_WORLD_PLAYER_PERSPECTIVE_ID = "demo_player_006";
const DEMO_WORLD_ADMIN_PERSPECTIVE_ID = "demo_player_002";

type Random = () => number;

type TeamDefinition = {
  identity: string;
  location: string;
  name: string;
  territory: string;
};

type PositionDefinition = {
  abbreviation: string;
  engine: PlayerPosition | null;
  label: string;
};

function xmur3(value: string) {
  let hash = 1779033703 ^ value.length;
  for (let index = 0; index < value.length; index += 1) {
    hash = Math.imul(hash ^ value.charCodeAt(index), 3432918353);
    hash = hash << 13 | hash >>> 19;
  }
  return () => {
    hash = Math.imul(hash ^ hash >>> 16, 2246822507);
    hash = Math.imul(hash ^ hash >>> 13, 3266489909);
    return (hash ^= hash >>> 16) >>> 0;
  };
}

function mulberry32(seed: number): Random {
  return () => {
    let value = seed += 0x6d2b79f5;
    value = Math.imul(value ^ value >>> 15, value | 1);
    value ^= value + Math.imul(value ^ value >>> 7, value | 61);
    return ((value ^ value >>> 14) >>> 0) / 4294967296;
  };
}

function seededRandom(seed: string) {
  return mulberry32(xmur3(seed)());
}

function pick<T>(random: Random, values: readonly T[]) {
  return values[Math.floor(random() * values.length)]!;
}

function shuffled<T>(random: Random, values: readonly T[]) {
  const result = [...values];
  for (let index = result.length - 1; index > 0; index -= 1) {
    const other = Math.floor(random() * (index + 1));
    [result[index], result[other]] = [result[other]!, result[index]!];
  }
  return result;
}

function pad(value: number, size = 3) {
  return String(value).padStart(size, "0");
}

function clamp(value: number, min = 0, max = 100) {
  return Math.max(min, Math.min(max, value));
}

function isoAtOffset(days: number, hour = 20, minutes = 30) {
  const value = new Date(DEMO_WORLD_NOW);
  value.setUTCDate(value.getUTCDate() + days);
  value.setUTCHours(hour, minutes, 0, 0);
  return value.toISOString();
}

const teamDefinitions: TeamDefinition[] = [
  { name: "Cobalto Raval", territory: "Barcelona", location: "Barcelona · Ciutat Vella", identity: "Juego corto, plantilla estable y noches de fútbol 7." },
  { name: "Circuit Poblenou", territory: "Barcelona", location: "Barcelona · Sant Martí", identity: "Ritmo alto, presión valiente y mucha rotación." },
  { name: "Brúixola Sants", territory: "Barcelona", location: "Barcelona · Sants-Montjuïc", identity: "Bloque ordenado que crece en los finales ajustados." },
  { name: "Onze del Clot", territory: "Barcelona", location: "Barcelona · El Clot", identity: "Equipo técnico con gusto por el pase interior." },
  { name: "Marina Fosca", territory: "Barcelona", location: "Barcelona · Barceloneta", identity: "Transiciones rápidas y partidos abiertos." },
  { name: "Ferro Sant Andreu", territory: "Barcelona", location: "Barcelona · Sant Andreu", identity: "Defensa intensa y portería muy fiable." },
  { name: "Diagonal 26", territory: "Barcelona", location: "Barcelona · Les Corts", identity: "Plantilla equilibrada que mezcla sala y fútbol 7." },
  { name: "Vértice Gràcia", territory: "Barcelona", location: "Barcelona · Gràcia", identity: "Talento entre líneas y una comunidad muy activa." },
  { name: "Pols Sabadell", territory: "Vallès", location: "Sabadell · Centre", identity: "Regularidad semanal y mucha cantera de barrio." },
  { name: "Carboni Terrassa", territory: "Vallès", location: "Terrassa · Nord", identity: "Equipo físico, directo y difícil de remontar." },
  { name: "Metro Rubí", territory: "Vallès", location: "Rubí · Centre", identity: "Pachanga rápida con laterales muy ofensivos." },
  { name: "Nexe Granollers", territory: "Vallès", location: "Granollers · Est", identity: "Juego asociativo y retos muy igualados." },
  { name: "Línia Cerdanyola", territory: "Vallès", location: "Cerdanyola · Centre", identity: "Orden táctico y mucha continuidad en la plantilla." },
  { name: "Vector Sant Cugat", territory: "Vallès", location: "Sant Cugat · Volpelleres", identity: "Equipo técnico que busca rivales nuevos." },
  { name: "Ronda Mollet", territory: "Vallès", location: "Mollet · Centre", identity: "Bloque compacto, vertical y competitivo." },
  { name: "Taller Barberà", territory: "Vallès", location: "Barberà · Centre", identity: "Grupo veterano que rara vez pierde el orden." },
  { name: "Riu Girona", territory: "Girona", location: "Girona · Eixample", identity: "Circulación paciente y delanteros móviles." },
  { name: "Marge Salt", territory: "Girona", location: "Salt · Centre", identity: "Presión alta y partidos de mucha energía." },
  { name: "Estany Banyoles", territory: "Girona", location: "Banyoles · Centre", identity: "Equipo sereno, eficaz y muy local." },
  { name: "Tramuntana 9", territory: "Girona", location: "Figueres · Centre", identity: "Juego exterior y golpeo desde media distancia." },
  { name: "Costa Blanes", territory: "Girona", location: "Blanes · Mas Florit", identity: "Plantilla rápida con preferencia por fútbol 7." },
  { name: "Volcà Olot", territory: "Girona", location: "Olot · Pla de Dalt", identity: "Intensidad constante y defensa adelantada." },
  { name: "Marea Mataró", territory: "Maresme", location: "Mataró · Centre", identity: "Ataque ancho y buen ritmo de retos." },
  { name: "Fòrum Badalona", territory: "Maresme", location: "Badalona · Gorg", identity: "Equipo de toque que compite sin perder la calma." },
  { name: "Premià Set", territory: "Maresme", location: "Premià · Centre", identity: "Especialistas en fútbol 7 y finales cerrados." },
  { name: "Nord Masnou", territory: "Maresme", location: "El Masnou · Ocata", identity: "Grupo joven con mucha llegada desde segunda línea." },
  { name: "Blau Vilassar", territory: "Maresme", location: "Vilassar · Centre", identity: "Plantilla equilibrada y abierta a nuevos rivales." },
  { name: "Riera Arenys", territory: "Maresme", location: "Arenys · Centre", identity: "Juego directo, buena portería y mucho compromiso." },
  { name: "Delta Castelldefels", territory: "Barcelona", location: "Castelldefels · Centre", identity: "Salida limpia, extremos rápidos y retos de proximidad." },
  { name: "Bosc Cardedeu", territory: "Vallès", location: "Cardedeu · Centre", identity: "Plantilla nueva que construye su identidad partido a partido." },
];

const venues: DemoWorldVenue[] = [
  ["Barcelona", "Barcelona · Sant Martí", "Pista Demo Llevant"],
  ["Barcelona", "Barcelona · Sants-Montjuïc", "Camp Demo Mirador"],
  ["Barcelona", "Barcelona · Sant Andreu", "Complex Demo Nord"],
  ["Vallès", "Sabadell · Centre", "Camp Demo Vapor"],
  ["Vallès", "Terrassa · Nord", "Pista Demo Carboni"],
  ["Vallès", "Sant Cugat · Centre", "Camp Demo Vector"],
  ["Girona", "Girona · Eixample", "Camp Demo Riu"],
  ["Girona", "Figueres · Centre", "Pista Demo Vent"],
  ["Maresme", "Mataró · Centre", "Camp Demo Marina"],
  ["Maresme", "Badalona · Gorg", "Pista Demo Fòrum"],
].map(([territory, publicLocation, label], index) => ({
  id: `demo_venue_${pad(index + 1, 2)}`,
  kind: index % 4 === 0 ? "sala" : "futbol7",
  label,
  publicLocation,
  territory,
}));

const firstNames = [
  "Adrià", "Aitor", "Álex", "Arnau", "Biel", "Bruno", "Dani", "Eloi", "Enzo", "Eric", "Ferran", "Gael", "Guillem", "Héctor",
  "Hugo", "Iker", "Ismael", "Jan", "Joel", "Jon", "Leo", "Lucas", "Marc", "Martí", "Mateo", "Nil", "Oriol", "Pau", "Pol", "Raúl",
  "Roc", "Samu", "Sergi", "Teo", "Unai", "Víctor", "Yago",
] as const;

const lastNames = [
  "Alenyà", "Borrell", "Cabot", "Cendra", "Dalmau", "Esteve", "Falcó", "Ferrer", "Grau", "Jové", "Lladó", "Miret", "Nadal", "Noguera",
  "Oliva", "Padró", "Quer", "Riba", "Rius", "Roig", "Soler", "Tena", "Valls", "Vidal", "Zamora",
] as const;

const positions: PositionDefinition[] = [
  { abbreviation: "POR", engine: null, label: "Portero" },
  { abbreviation: "DFC", engine: "centre_back", label: "Defensa central" },
  { abbreviation: "LD", engine: "full_back", label: "Lateral derecho" },
  { abbreviation: "LI", engine: "full_back", label: "Lateral izquierdo" },
  { abbreviation: "PIV", engine: "defensive_midfielder", label: "Pivote defensivo" },
  { abbreviation: "MC", engine: "central_midfielder", label: "Mediocentro" },
  { abbreviation: "MCO", engine: "attacking_midfielder", label: "Mediapunta" },
  { abbreviation: "ED", engine: "winger", label: "Extremo derecho" },
  { abbreviation: "EI", engine: "winger", label: "Extremo izquierdo" },
  { abbreviation: "DC", engine: "striker", label: "Delantero centro" },
  { abbreviation: "DFC", engine: "centre_back", label: "Defensa central" },
];

const positionBoosts: Record<PlayerPosition, Partial<AttributeRatings>> = {
  centre_back: { defending: 16, physical: 10, shooting: -8 },
  full_back: { pace: 10, defending: 8, shooting: -4 },
  defensive_midfielder: { defending: 10, passing: 8, physical: 6 },
  central_midfielder: { passing: 12, dribbling: 5 },
  attacking_midfielder: { passing: 10, dribbling: 10, shooting: 5 },
  winger: { pace: 14, dribbling: 12, defending: -8 },
  striker: { shooting: 16, pace: 6, defending: -12 },
};

const playerCosmeticKeys = new Set(PLAYER_COSMETIC_CATALOG.map((item) => item.key));
const teamCosmeticKeys = new Set(TEAM_SHIELD_RENDER_CATALOG.filter((item) => !item.prototype).map((item) => item.key));

function playerLoadout(random: Random, index: number): PlayerCosmeticLoadout {
  if (index % 5 === 0) return { ...EMPTY_PLAYER_COSMETIC_LOADOUT };
  const candidates = {
    accentKey: [null, "player.accent.copper", "player.accent.navy"],
    backgroundKey: [null, "player.background.asphalt_night", "player.background.grid_iq"],
    effectKey: [null, null, "player.effect.spotlights", "player.effect.iq_scan"],
    frameKey: [null, "player.frame.barrio.steel", "player.frame.barrio.copper", "player.frame.barrio.silver", "player.frame.future.navy"],
    titleKey: [null, null, "player.title.old_school", "player.title.team_engine"],
  } as const;
  const loadout: PlayerCosmeticLoadout = {
    accentKey: pick(random, candidates.accentKey),
    backgroundKey: pick(random, candidates.backgroundKey),
    effectKey: pick(random, candidates.effectKey),
    featuredBadgeGrantId: null,
    frameKey: pick(random, candidates.frameKey),
    titleKey: pick(random, candidates.titleKey),
  };
  for (const key of [loadout.accentKey, loadout.backgroundKey, loadout.effectKey, loadout.frameKey, loadout.titleKey]) {
    if (key && !playerCosmeticKeys.has(key)) throw new Error(`Unknown player cosmetic ${key}`);
  }
  return loadout;
}

function ratingFor(random: Random, position: PositionDefinition, teamIndex: number) {
  const baseLevel = 48 + Math.round(random() * 24) + (teamIndex < 4 ? 3 : 0);
  const baseFacets = ATTRIBUTE_KEYS.reduce((result, facet) => {
    const boost = position.engine ? positionBoosts[position.engine][facet] ?? 0 : facet === "defending" ? 12 : 0;
    result[facet] = clamp(baseLevel + boost + Math.round((random() - 0.5) * 14), 30, 92);
    return result;
  }, {} as AttributeRatings);
  const reliability = 52 + Math.round(random() * 38);
  const evidenceCount = 3 + Math.floor(random() * 5);

  if (!position.engine) {
    return {
      currentFacets: baseFacets,
      currentOverall: null,
      domain: "goalkeeper_legacy" as const,
      engineVersion: RATING_SYSTEM_V2_ENGINE_VERSION,
      evaluatorCount: evidenceCount,
      reliability,
    };
  }

  const evidence = Array.from({ length: evidenceCount }, () => ({
    evaluatorConfidence: 55 + Math.round(random() * 40),
    observations: ATTRIBUTE_KEYS.reduce((result, facet) => {
      result[facet] = clamp(baseFacets[facet] + Math.round((random() - 0.5) * 12));
      return result;
    }, {} as AttributeRatings),
  }));
  const layers = calculateRatingCardLayers({
    baseFacets,
    baseReliability: reliability,
    currentModifiers: {},
    domain: "field",
    evidence,
    primaryPosition: position.engine,
  });
  return {
    currentFacets: layers.currentFacets,
    currentOverall: layers.currentOverall,
    domain: "field" as const,
    engineVersion: layers.engineVersion,
    evaluatorCount: layers.evaluatorCount,
    reliability: layers.reliability,
  };
}

function shieldFor(index: number, stats?: DemoWorldTeam["stats"]): { config: TeamShieldConfig; unlocked: string[] } {
  const shapes = ["team.shield.shape.classic_iq", "team.shield.shape.round", "team.shield.shape.tall", "team.shield.shape.swiss", "team.shield.shape.hex_iq", "team.shield.shape.diamond", "team.shield.shape.modern", "team.shield.shape.barrio"];
  const colors = ["team.shield.color.midnight", "team.shield.color.crimson", "team.shield.color.emerald", "team.shield.color.amber"];
  const secondary = ["team.shield.color.cyan", "team.shield.color.ivory", "team.shield.color.amber"];
  const symbols = ["team.shield.symbol.ball_iq", "team.shield.symbol.monogram", "team.shield.symbol.star_iq", "team.shield.symbol.bolt", "team.shield.symbol.tower"];
  const patterns = ["team.shield.pattern.diagonal", "team.shield.pattern.stripes", "team.shield.pattern.chevron", "team.shield.pattern.none"];
  const unlocked: string[] = [];
  if (stats?.challengeWins) unlocked.push("team.shield.border.copper");
  if ((stats?.challengesPlayed ?? 0) >= 10) unlocked.push("team.shield.ornament.banner");
  if ((stats?.matchesPlayed ?? 0) >= 25) unlocked.push("team.shield.ornament.laurels");
  if ((stats?.matchesPlayed ?? 0) >= 50) unlocked.push("team.shield.border.silver");
  if (stats?.cleanSheets) unlocked.push("team.shield.effect.edge_glow");

  const config: TeamShieldConfig = {
    ...TEAM_SHIELD_DEFAULT_CONFIG,
    backgroundKey: index % 3 === 0 ? "team.shield.background.split" : "team.shield.background.duotone",
    borderKey: unlocked.includes("team.shield.border.silver")
      ? "team.shield.border.silver"
      : unlocked.includes("team.shield.border.copper") ? "team.shield.border.copper" : index % 3 === 0 ? "team.shield.border.double" : "team.shield.border.clean",
    bottomOrnamentKey: unlocked.includes("team.shield.ornament.banner") ? "team.shield.ornament.banner" : null,
    effectKey: unlocked.includes("team.shield.effect.edge_glow") ? "team.shield.effect.edge_glow" : null,
    foundationYear: String(2012 + index % 13),
    initials: teamDefinitions[index]!.name.split(" ").map((part) => part[0]).join("").slice(0, 3).toUpperCase(),
    patternKey: patterns[index % patterns.length]!,
    primaryColorKey: colors[index % colors.length]!,
    primarySymbolKey: symbols[index % symbols.length]!,
    primarySymbolRotation: index % 3 === 0 ? -4 : index % 3 === 1 ? 0 : 4,
    primarySymbolScale: index % 2 === 0 ? 1 : 0.94,
    secondaryColorKey: secondary[index % secondary.length]!,
    shapeKey: shapes[index % shapes.length]!,
    sideOrnamentKey: unlocked.includes("team.shield.ornament.laurels") ? "team.shield.ornament.laurels" : null,
  };
  for (const key of [config.shapeKey, config.backgroundKey, config.patternKey, config.primaryColorKey, config.secondaryColorKey, config.primarySymbolKey, config.borderKey, config.bottomOrnamentKey, config.sideOrnamentKey, config.effectKey]) {
    if (key && !teamCosmeticKeys.has(key)) throw new Error(`Unknown active team cosmetic ${key}`);
  }
  return { config, unlocked };
}

function emptyTeamStats(): DemoWorldTeam["stats"] {
  return { challengeDraws: 0, challengeLosses: 0, challengesPlayed: 0, challengeWins: 0, cleanSheets: 0, goalsAgainst: 0, goalsFor: 0, matchesPlayed: 0 };
}

function buildTeams(): DemoWorldTeam[] {
  return teamDefinitions.map((definition, index) => ({
    foundedYear: String(2012 + index % 13),
    id: `demo_team_${pad(index + 1)}`,
    identity: definition.identity,
    memberCount: positions.length,
    name: definition.name,
    openToChallenges: index % 5 !== 4,
    publicLocation: definition.location,
    rankingLabel: "Clasificación Demo",
    shield: shieldFor(index).config,
    stats: emptyTeamStats(),
    territory: definition.territory,
    unlockedCosmeticKeys: [],
  }));
}

function buildPlayers(random: Random, teams: DemoWorldTeam[]): DemoWorldPlayer[] {
  let playerIndex = 0;
  const players = teams.flatMap((team, teamIndex) => positions.map((position, rosterIndex) => {
    playerIndex += 1;
    const name = `${firstNames[(playerIndex * 7 + teamIndex * 3) % firstNames.length]} ${lastNames[(playerIndex * 11 + rosterIndex * 5) % lastNames.length]}`;
    return {
      appearances: 0,
      assists: 0,
      avatarHue: Math.round((teamIndex * 47 + rosterIndex * 29) % 360),
      birthYear: 1978 + Math.floor(random() * 24),
      cosmetics: playerLoadout(random, playerIndex),
      featuredAchievementKey: null,
      goals: 0,
      id: `demo_player_${pad(playerIndex)}`,
      market: {
        availability: pick(random, ["Entre semana por la noche", "Viernes noche", "Fines de semana", "Martes y jueves", "Con aviso de 48 horas"]),
        modalities: rosterIndex % 4 === 0 ? ["sala", "futbol7"] : rosterIndex % 5 === 0 ? ["futbol7", "futbol11"] : ["futbol7"],
        openToGuest: playerIndex % 7 === 0,
        publicBio: pick(random, [
          "Me gusta jugar fácil y mantener el equipo ordenado.",
          "Disponible para completar partidos igualados por la zona.",
          "Prefiero grupos estables y partidos con buen ambiente.",
          "Puedo cubrir varias posiciones según lo que falte.",
        ]),
        zones: [team.publicLocation, team.territory],
      },
      name,
      position,
      rating: ratingFor(random, position, teamIndex),
      teamId: team.id,
      wins: 0,
    } satisfies DemoWorldPlayer;
  }));

  playerIndex += 1;
  const freeAgentPosition = positions[5]!;
  players.push({
    appearances: 18,
    assists: 11,
    avatarHue: 174,
    birthYear: 1994,
    cosmetics: {
      ...EMPTY_PLAYER_COSMETIC_LOADOUT,
      backgroundKey: "player.background.grid_iq",
      frameKey: "player.frame.barrio.steel",
    },
    featuredAchievementKey: "player.internal.matches.005",
    goals: 7,
    id: `demo_player_${pad(playerIndex)}`,
    market: {
      availability: "Martes y jueves a partir de las 20:00",
      modalities: ["sala", "futbol7"],
      openToGuest: true,
      publicBio: "Busco un grupo estable en Barcelona o Vallès. Juego de mediocentro y priorizo el pase.",
      zones: ["Barcelona", "Vallès"],
    },
    name: "Nico Valira",
    position: freeAgentPosition,
    rating: ratingFor(random, freeAgentPosition, 10),
    teamId: null,
    wins: 10,
  });
  return players;
}

function playersForTeam(players: DemoWorldPlayer[], teamId: string) {
  return players.filter((player) => player.teamId === teamId);
}

function scorerRows(random: Random, playerIds: string[], goals: number, side: "away" | "home") {
  if (goals <= 0) return [];
  const candidates = playerIds.slice(1).length ? playerIds.slice(1) : playerIds;
  const counts = new Map<string, number>();
  for (let goal = 0; goal < goals; goal += 1) {
    const playerId = pick(random, candidates);
    counts.set(playerId, (counts.get(playerId) ?? 0) + 1);
  }
  return [...counts].map(([playerId, count]) => ({ goals: count, playerId, side }));
}

function modalityFor(index: number): DemoMatchKind {
  return index % 9 === 0 ? "sala" : index % 13 === 0 ? "futbol11" : "futbol7";
}

function lineupSize(kind: DemoMatchKind) {
  return kind === "sala" ? 5 : kind === "futbol11" ? 6 : 6;
}

function makeInternalMatch(random: Random, index: number, team: DemoWorldTeam, roster: DemoWorldPlayer[]): DemoWorldMatch {
  const kind = modalityFor(index);
  const shuffledRoster = shuffled(random, roster);
  const sideSize = lineupSize(kind);
  const homePlayerIds = shuffledRoster.slice(0, sideSize).map((player) => player.id);
  const awayPlayerIds = shuffledRoster.slice(sideSize, sideSize * 2).map((player) => player.id);
  const home = index % 12 === 0 ? 0 : Math.floor(random() * 6);
  const away = index % 12 === 0 ? 0 : Math.floor(random() * 6);
  const date = isoAtOffset(-4 - index * 3, 19 + index % 3, index % 2 ? 30 : 0);
  return {
    awayLabel: "Equipo Rojo",
    awayPlayerIds,
    awayTeamId: null,
    confirmedPlayerIds: [...homePlayerIds, ...awayPlayerIds],
    date,
    homeLabel: "Equipo Azul",
    homePlayerIds,
    homeTeamId: team.id,
    id: `demo_match_${pad(index + 1)}`,
    kind,
    publicOpenSlots: 0,
    reservePlayerIds: shuffledRoster.slice(sideSize * 2, sideSize * 2 + 1).map((player) => player.id),
    result: { away, home },
    revision: 3 + index % 11,
    scope: "internal",
    scorers: [
      ...scorerRows(random, homePlayerIds, home, "home"),
      ...scorerRows(random, awayPlayerIds, away, "away"),
    ],
    status: "finalized",
    title: `${team.name} · jornada interna ${index + 1}`,
    venueId: venues.find((venue) => venue.territory === team.territory)?.id ?? venues[0]!.id,
  };
}

function makeExternalMatch(random: Random, index: number, matchIndex: number, homeTeam: DemoWorldTeam, awayTeam: DemoWorldTeam, players: DemoWorldPlayer[]): DemoWorldMatch {
  const kind = modalityFor(matchIndex);
  const sideSize = lineupSize(kind);
  const homeRoster = shuffled(random, playersForTeam(players, homeTeam.id));
  const awayRoster = shuffled(random, playersForTeam(players, awayTeam.id));
  const featuredPlayer = index === 0 ? homeRoster.find((player) => player.id === DEMO_WORLD_PLAYER_PERSPECTIVE_ID) : null;
  const homePlayerIds = featuredPlayer
    ? [featuredPlayer, ...homeRoster.filter((player) => player.id !== featuredPlayer.id)].slice(0, sideSize).map((player) => player.id)
    : homeRoster.slice(0, sideSize).map((player) => player.id);
  const awayPlayerIds = awayRoster.slice(0, sideSize).map((player) => player.id);
  const forced = index === 0 ? { home: 3, away: 0 } : index === 10 ? { home: 2, away: 1 } : null;
  const home = forced?.home ?? Math.floor(random() * 6);
  const away = forced?.away ?? Math.floor(random() * 6);
  return {
    awayLabel: awayTeam.name,
    awayPlayerIds,
    awayTeamId: awayTeam.id,
    confirmedPlayerIds: [...homePlayerIds, ...awayPlayerIds],
    date: isoAtOffset(-6 - index * 4, 20 + index % 2, index % 3 ? 30 : 0),
    homeLabel: homeTeam.name,
    homePlayerIds,
    homeTeamId: homeTeam.id,
    id: `demo_match_${pad(matchIndex + 1)}`,
    kind,
    publicOpenSlots: 0,
    reservePlayerIds: [],
    result: { away, home },
    revision: 5 + index % 13,
    scope: "challenge",
    scorers: index === 0
      ? [{ goals: 3, playerId: DEMO_WORLD_PLAYER_PERSPECTIVE_ID, side: "home" }]
      : [
        ...scorerRows(random, homePlayerIds, home, "home"),
        ...scorerRows(random, awayPlayerIds, away, "away"),
      ],
    status: "finalized",
    title: `${homeTeam.name} vs ${awayTeam.name}`,
    venueId: venues.find((venue) => venue.territory === homeTeam.territory)?.id ?? venues[0]!.id,
  };
}

function buildMatches(random: Random, teams: DemoWorldTeam[], players: DemoWorldPlayer[]) {
  const matches: DemoWorldMatch[] = [];
  const teamOneRoster = playersForTeam(players, teams[0]!.id);
  const teamTwoRoster = playersForTeam(players, teams[1]!.id);
  for (let index = 0; index < 50; index += 1) matches.push(makeInternalMatch(random, index, teams[0]!, teamOneRoster));
  for (let index = 0; index < 25; index += 1) matches.push(makeInternalMatch(random, index + 50, teams[1]!, teamTwoRoster));

  const pairs: Array<[number, number]> = [];
  for (let index = 0; index < 10; index += 1) pairs.push([0, 2 + index]);
  for (let index = 0; index < 10; index += 1) pairs.push([1, 12 + index]);
  for (let index = 0; index < 25; index += 1) {
    const nonFeaturedTeamCount = teams.length - 2;
    const home = 2 + index % nonFeaturedTeamCount;
    const away = 2 + (index * 7 + 5) % nonFeaturedTeamCount;
    pairs.push(home === away ? [home, (away + 1) % teams.length] : [home, away]);
  }
  pairs.forEach(([home, away], index) => {
    matches.push(makeExternalMatch(random, index, matches.length, teams[home]!, teams[away]!, players));
  });

  for (let index = 0; index < 8; index += 1) {
    const homeTeam = teams[index]!
    const awayTeam = teams[(index * 3 + 9) % teams.length]!;
    const kind = modalityFor(matches.length);
    const sideSize = lineupSize(kind);
    const homeRoster = shuffled(random, playersForTeam(players, homeTeam.id));
    const awayRoster = shuffled(random, playersForTeam(players, awayTeam.id));
    const homePlayerIds = homeRoster.slice(0, Math.max(3, sideSize - 1)).map((player) => player.id);
    const awayPlayerIds = awayRoster.slice(0, Math.max(3, sideSize - 2)).map((player) => player.id);
    matches.push({
      awayLabel: awayTeam.name,
      awayPlayerIds,
      awayTeamId: awayTeam.id,
      confirmedPlayerIds: [...homePlayerIds, ...awayPlayerIds],
      date: isoAtOffset(2 + index * 2, 19 + index % 3, index % 2 ? 30 : 0),
      homeLabel: homeTeam.name,
      homePlayerIds,
      homeTeamId: homeTeam.id,
      id: `demo_match_${pad(matches.length + 1)}`,
      kind,
      publicOpenSlots: Math.max(0, sideSize * 2 - homePlayerIds.length - awayPlayerIds.length),
      reservePlayerIds: homeRoster.slice(sideSize - 1, sideSize + 1).map((player) => player.id),
      result: null,
      revision: 8 + index,
      scope: "challenge",
      scorers: [],
      status: "scheduled",
      title: `${homeTeam.name} vs ${awayTeam.name}`,
      venueId: venues.find((venue) => venue.territory === homeTeam.territory)?.id ?? venues[0]!.id,
    });
  }
  return matches.sort((left, right) => Date.parse(right.date) - Date.parse(left.date));
}

function applyMatchStats(teams: DemoWorldTeam[], players: DemoWorldPlayer[], matches: DemoWorldMatch[]) {
  const teamById = new Map(teams.map((team) => [team.id, team]));
  const playerById = new Map(players.map((player) => [player.id, player]));
  for (const match of matches.filter((entry) => entry.status === "finalized" && entry.result)) {
    const result = match.result!;
    const homeTeam = teamById.get(match.homeTeamId)!;
    homeTeam.stats.matchesPlayed += 1;
    if (match.scope === "challenge" && match.awayTeamId) {
      const awayTeam = teamById.get(match.awayTeamId)!;
      awayTeam.stats.matchesPlayed += 1;
      homeTeam.stats.challengesPlayed += 1;
      awayTeam.stats.challengesPlayed += 1;
      homeTeam.stats.goalsFor += result.home;
      homeTeam.stats.goalsAgainst += result.away;
      awayTeam.stats.goalsFor += result.away;
      awayTeam.stats.goalsAgainst += result.home;
      if (result.away === 0) homeTeam.stats.cleanSheets += 1;
      if (result.home === 0) awayTeam.stats.cleanSheets += 1;
      if (result.home > result.away) {
        homeTeam.stats.challengeWins += 1;
        awayTeam.stats.challengeLosses += 1;
      } else if (result.away > result.home) {
        awayTeam.stats.challengeWins += 1;
        homeTeam.stats.challengeLosses += 1;
      } else {
        homeTeam.stats.challengeDraws += 1;
        awayTeam.stats.challengeDraws += 1;
      }
    }

    for (const playerId of [...match.homePlayerIds, ...match.awayPlayerIds]) {
      const player = playerById.get(playerId);
      if (player) player.appearances += 1;
    }
    const homeWon = result.home > result.away;
    const awayWon = result.away > result.home;
    for (const playerId of homeWon ? match.homePlayerIds : awayWon ? match.awayPlayerIds : []) {
      const player = playerById.get(playerId);
      if (player) player.wins += 1;
    }
    for (const scorer of match.scorers) {
      const player = playerById.get(scorer.playerId);
      if (!player) continue;
      player.goals += scorer.goals;
      const teammates = scorer.side === "home" ? match.homePlayerIds : match.awayPlayerIds;
      const assister = teammates.find((playerId) => playerId !== scorer.playerId);
      if (assister) playerById.get(assister)!.assists += Math.min(1, scorer.goals);
    }
  }

  teams.forEach((team, index) => {
    const { config, unlocked } = shieldFor(index, team.stats);
    team.shield = config;
    team.unlockedCosmeticKeys = unlocked;
  });
  players.forEach((player) => {
    if (player.goals >= 3) player.featuredAchievementKey = "player.all.hat_tricks.001";
    else if (player.appearances >= 25) player.featuredAchievementKey = "player.all.matches.025";
    else if (player.appearances >= 5) player.featuredAchievementKey = "player.internal.matches.005";
  });
}

function rankingsFor(teams: DemoWorldTeam[]): DemoWorldRankingRow[] {
  return teams
    .map((team) => ({
      draws: team.stats.challengeDraws,
      goalsAgainst: team.stats.goalsAgainst,
      goalsFor: team.stats.goalsFor,
      losses: team.stats.challengeLosses,
      played: team.stats.challengesPlayed,
      points: team.stats.challengeWins * 3 + team.stats.challengeDraws,
      position: 0,
      teamId: team.id,
      wins: team.stats.challengeWins,
    }))
    .sort((left, right) => right.points - left.points || (right.goalsFor - right.goalsAgainst) - (left.goalsFor - left.goalsAgainst) || left.teamId.localeCompare(right.teamId))
    .map((entry, index) => ({ ...entry, position: index + 1 }));
}

function seasonScore(quality: number, competition: number, opposition: number) {
  return Number((quality * 0.55 + competition * 0.3 + opposition * 0.15).toFixed(2));
}

function provincialRankingFor(players: DemoWorldPlayer[]): DemoWorldProvincialRanking {
  const perspectivePlayer = players.find((player) => player.id === DEMO_WORLD_PLAYER_PERSPECTIVE_ID)!;
  const candidates = players.filter((player) => player.rating.domain === "field" && player.id !== perspectivePlayer.id);
  const ordered = [...candidates.slice(0, 26), perspectivePlayer, ...candidates.slice(26, 31)];
  const entries = ordered.map((player, index) => {
    const position = index + 1;
    const quality = Number((94 - position * 0.62).toFixed(2));
    const competition = Number((91 - position * 0.68).toFixed(2));
    const opposition = Number((89 - position * 0.48).toFixed(2));
    return {
      components: { competition, opposition, quality },
      displayName: player.name,
      eligibilityState: "eligible" as const,
      entryKey: `demo_ranking_entry_${pad(position, 2)}`,
      logicalOpponents: 6 + position % 9,
      position,
      recentActivityWeeks: 1 + position % 10,
      reliability: Math.max(45, player.rating.reliability) / 100,
      score: seasonScore(quality, competition, opposition),
      validChallenges: 15 + position % 12,
    };
  });
  const ownEntry = entries.find((entry) => entry.position === 27)!;
  const showcasePlayers = candidates.slice(40, 43);
  const publication = {
    checksum: canonicalHash(entries),
    publishedAt: isoAtOffset(-1, 8, 0),
    revision: 17,
  };
  return {
    awardsEnabled: false,
    formula: {
      activityWindowWeeks: 12,
      minimumLogicalOpponents: 6,
      minimumRatingReliability: 0.45,
      minimumValidChallenges: 15,
      weights: { competition: 0.3, opposition: 0.15, quality: 0.55 },
    },
    ranking: {
      available: true,
      items: entries.slice(0, 10),
      pagination: { offset: 0, pageSize: 10, total: entries.length },
      publication,
      season: {
        endsAt: "2027-06-30T21:59:59.000Z",
        formulaKey: "season_score_v3",
        formulaVersion: 3,
        id: "demo_season_2026_27",
        key: "2026-27",
        label: DEMO_WORLD_SEASON,
        startsAt: "2026-07-01T00:00:00.000Z",
        status: "active",
      },
      territory: { provinceCode: "08", provinceName: "Barcelona" },
    },
    showcases: {
      "my-rank": {
        available: true,
        displayName: perspectivePlayer.name,
        entryKey: ownEntry.entryKey,
        eligibilityState: "eligible",
        logicalOpponents: ownEntry.logicalOpponents,
        position: 27,
        provinceCode: "08",
        publicationRevision: publication.revision,
        recentActivityWeeks: ownEntry.recentActivityWeeks,
        reliability: ownEntry.reliability,
        score: ownEntry.score,
        validChallenges: ownEntry.validChallenges,
      },
      ineligible: {
        available: true,
        displayName: showcasePlayers[0]!.name,
        eligibilityState: "ineligible",
        logicalOpponents: 4,
        position: null,
        provinceCode: "08",
        publicationRevision: publication.revision,
        reasonCodes: ["ranking_evidence_incomplete"],
        recentActivityWeeks: 5,
        reliability: 0.62,
        score: 0,
        validChallenges: 9,
      },
      provisional: {
        available: true,
        displayName: showcasePlayers[1]!.name,
        eligibilityState: "provisional",
        logicalOpponents: 5,
        position: null,
        provinceCode: "08",
        publicationRevision: publication.revision,
        reasonCodes: ["ranking_evidence_incomplete"],
        recentActivityWeeks: 2,
        reliability: 0.71,
        score: 61.24,
        validChallenges: 13,
      },
      "pending-review": {
        available: true,
        displayName: showcasePlayers[2]!.name,
        eligibilityState: "pending_integrity_review",
        logicalOpponents: 8,
        position: null,
        provinceCode: "08",
        publicationRevision: publication.revision,
        reasonCodes: ["ranking_review_pending"],
        recentActivityWeeks: 3,
        reliability: 0.78,
        score: 67.18,
        validChallenges: 19,
      },
    },
  };
}

function attendanceFor(matches: DemoWorldMatch[], players: DemoWorldPlayer[]): DemoWorldAttendanceRecord[] {
  const rosterByTeam = new Map<string, DemoWorldPlayer[]>();
  for (const player of players) {
    if (!player.teamId) continue;
    rosterByTeam.set(player.teamId, [...(rosterByTeam.get(player.teamId) ?? []), player]);
  }
  const records: DemoWorldAttendanceRecord[] = [];
  const absenceStatuses = ["excused_absence", "late_cancellation", "unexcused_no_show"] as const;
  for (const [matchIndex, match] of matches.filter((entry) => entry.status === "finalized").slice(0, 42).entries()) {
    const playedIds = [...match.homePlayerIds.slice(0, 2), ...match.awayPlayerIds.slice(0, 1)];
    for (const playerId of playedIds) {
      records.push({
        id: `demo_attendance_${pad(records.length + 1)}`,
        matchId: match.id,
        playerId,
        recordedAt: match.date,
        status: "played",
      });
    }
    const absentPlayer = (rosterByTeam.get(match.homeTeamId) ?? []).find((player) => !match.homePlayerIds.includes(player.id));
    if (absentPlayer) {
      if (!match.confirmedPlayerIds.includes(absentPlayer.id)) match.confirmedPlayerIds.push(absentPlayer.id);
      records.push({
        id: `demo_attendance_${pad(records.length + 1)}`,
        matchId: match.id,
        playerId: absentPlayer.id,
        recordedAt: match.date,
        status: absenceStatuses[matchIndex % absenceStatuses.length]!,
      });
    }
  }
  return records;
}

function teamAchievements(teams: DemoWorldTeam[]) {
  const achievements: DemoWorldAchievement[] = [];
  let index = 0;
  for (const team of teams) {
    const evidenceRows = [
      team.stats.challengeWins >= 1 ? [DEMO_WORLD_TEAM_REWARD_MAPPINGS[0], `Primera victoria confirmada entre ${team.stats.challengeWins} victorias externas.`] : null,
      team.stats.challengesPlayed >= 10 ? [DEMO_WORLD_TEAM_REWARD_MAPPINGS[1], `${team.stats.challengesPlayed} retos finalizados.`] : null,
      team.stats.matchesPlayed >= 25 ? [DEMO_WORLD_TEAM_REWARD_MAPPINGS[2], `${team.stats.matchesPlayed} partidos finalizados.`] : null,
      team.stats.matchesPlayed >= 50 ? [DEMO_WORLD_TEAM_REWARD_MAPPINGS[3], `${team.stats.matchesPlayed} partidos finalizados.`] : null,
      team.stats.cleanSheets >= 1 ? [DEMO_WORLD_TEAM_REWARD_MAPPINGS[4], `${team.stats.cleanSheets} porterías a cero confirmadas.`] : null,
    ].filter(Boolean) as Array<[typeof DEMO_WORLD_TEAM_REWARD_MAPPINGS[number], string]>;
    for (const [mapping, evidence] of evidenceRows) {
      index += 1;
      achievements.push({
        description: `${mapping.label} desbloquea ${mapping.cosmeticKey}.`,
        evidence,
        id: `demo_achievement_team_${pad(index)}`,
        key: mapping.achievementKey,
        occurredAt: isoAtOffset(-60 + index),
        rarity: mapping.mappingKey === "fifty_matches" ? "epic" : mapping.mappingKey === "twenty_five_matches" || mapping.mappingKey === "first_clean_sheet" ? "rare" : "uncommon",
        subjectId: team.id,
        subjectType: "team",
        title: mapping.label,
      });
    }
  }
  return achievements;
}

function playerAchievements(players: DemoWorldPlayer[]) {
  const achievements: DemoWorldAchievement[] = [];
  let index = 0;
  const eligible = players.filter((entry) => entry.teamId).sort((left, right) => right.appearances - left.appearances);
  const featured = eligible.find((player) => player.id === DEMO_WORLD_PLAYER_PERSPECTIVE_ID)!;
  const ordered = [featured, ...eligible.filter((player) => player.id !== featured.id)].slice(0, 42);
  for (const player of ordered) {
    index += 1;
    const goalAchievement = player.goals >= 3;
    achievements.push({
      description: goalAchievement ? "Marcó tres o más goles en un partido confirmado." : "Superó cinco partidos confirmados con su grupo.",
      evidence: player.id === DEMO_WORLD_PLAYER_PERSPECTIVE_ID
        ? "3 goles confirmados en demo_match_076."
        : goalAchievement ? `${player.goals} goles acumulados en el snapshot.` : `${player.appearances} apariciones confirmadas.`,
      id: `demo_achievement_player_${pad(index)}`,
      key: goalAchievement ? "player.all.hat_tricks.001" : "player.internal.matches.005",
      occurredAt: isoAtOffset(-45 + index % 35),
      rarity: goalAchievement ? "rare" : "common",
      subjectId: player.id,
      subjectType: "player",
      title: goalAchievement ? "Hat-trick" : "Uno de los nuestros",
    });
  }
  return achievements;
}

function rewardBoxesFor(achievements: DemoWorldAchievement[]): DemoWorldRewardBox[] {
  const playerRewards = PLAYER_COSMETIC_CATALOG.map((item) => item.key);
  const featuredAchievement = achievements.find((achievement) => achievement.subjectId === DEMO_WORLD_PLAYER_PERSPECTIVE_ID && achievement.key === "player.all.hat_tricks.001")!;
  const ordered = [featuredAchievement, ...achievements.filter((achievement) => achievement.id !== featuredAchievement.id)].slice(0, 28);
  return ordered.map((achievement, index) => {
    const mapping = achievement.subjectType === "team"
      ? DEMO_WORLD_TEAM_REWARD_MAPPINGS.find((entry) => entry.achievementKey === achievement.key)
      : null;
    return {
      achievementId: achievement.id,
      id: `demo_reward_box_${pad(index + 1)}`,
      ownerId: achievement.subjectId,
      ownerType: achievement.subjectType,
      rarity: achievement.rarity,
      rewardCosmeticKey: achievement.id === featuredAchievement.id ? "player.frame.barrio.copper" : mapping?.cosmeticKey ?? playerRewards[index % playerRewards.length]!,
      state: index % 4 === 0 ? "pending" : "opened",
    };
  });
}

function challengesFor(matches: DemoWorldMatch[]) {
  return matches
    .filter((match) => match.scope === "challenge" && match.awayTeamId)
    .slice(0, 48)
    .map((match, index): DemoWorldChallenge => {
      const openStatuses = ["countered", "pending", "accepted", "rejected", "cancelled"] as const;
      const status: DemoWorldChallenge["status"] = match.status === "finalized" ? "completed" : openStatuses[index % openStatuses.length]!;
      return {
        awayTeamId: match.awayTeamId!,
        date: match.date,
        homeTeamId: match.homeTeamId,
        id: `demo_challenge_${pad(index + 1)}`,
        matchId: status === "accepted" || status === "completed" ? match.id : null,
        message: pick(seededRandom(`${DEMO_WORLD_SEED}:challenge:${index}`), [
          "Buscamos un partido igualado y con buen ambiente.",
          "Propuesta abierta a ajustar hora y modalidad.",
          "Revancha amistosa para cerrar la jornada.",
          "Primer cruce entre estos dos grupos de la zona.",
        ]),
        proposedKind: match.kind,
        status,
      };
    });
}

function notificationsFor(matches: DemoWorldMatch[], achievements: DemoWorldAchievement[], challenges: DemoWorldChallenge[], players: DemoWorldPlayer[]): DemoWorldNotification[] {
  const upcoming = matches.find((match) => match.status === "scheduled")!;
  const firstAchievement = achievements.find((entry) => entry.subjectId === "demo_team_001")!;
  const acceptedChallenge = challenges.find((challenge) => challenge.status === "accepted")!;
  const completedChallenge = challenges.find((challenge) => challenge.status === "completed")!;
  const counteredChallenge = challenges.find((challenge) => challenge.status === "countered")!;
  const freeAgent = players.find((player) => !player.teamId)!;
  const rows: Array<Omit<DemoWorldNotification, "createdAt" | "id">> = [
    { title: "Se apunta un jugador", body: "Joel Ferrer ha confirmado que va al próximo partido.", category: "match", mandatory: false, targetId: upcoming.id, targetTab: "partido" },
    { title: "Cambio de asistencia", body: "Un jugador confirmado ha cancelado con antelación.", category: "match", mandatory: false, targetId: upcoming.id, targetTab: "partido" },
    { title: "Alineación actualizada", body: "El admin ha publicado una nueva distribución de equipos.", category: "match", mandatory: true, targetId: upcoming.id, targetTab: "partido" },
    { title: "Reto aceptado", body: "El rival ha aceptado la fecha propuesta.", category: "challenge", mandatory: true, targetId: acceptedChallenge.id, targetTab: "mercado" },
    { title: "Contrapropuesta recibida", body: "Hay una nueva hora para revisar antes de confirmar.", category: "challenge", mandatory: true, targetId: counteredChallenge.id, targetTab: "mercado" },
    { title: "Solicitud para unirse", body: "Un jugador de Mercado quiere ocupar una plaza pública.", category: "market", mandatory: true, targetId: upcoming.id, targetTab: "mercado" },
    { title: "Nuevo miembro", body: "La plantilla suma un nuevo jugador registrado.", category: "group", mandatory: false, targetId: "demo_team_001", targetTab: "equipo" },
    { title: "Nuevo logro desbloqueado", body: "El equipo tiene una recompensa pendiente de reclamar.", category: "achievement", mandatory: false, targetId: firstAchievement.id, targetTab: "perfil" },
    { title: "Caja pendiente", body: "La caja de logro sigue cerrada y conserva su recompensa.", category: "achievement", mandatory: false, targetId: "demo_reward_box_001", targetTab: "perfil" },
    { title: "Resultado confirmado", body: "Los dos equipos han confirmado el marcador del último reto.", category: "challenge", mandatory: true, targetId: completedChallenge.id, targetTab: "partido" },
    { title: "Perfil de Mercado visto", body: "Dos equipos han guardado este perfil como posible refuerzo.", category: "market", mandatory: false, targetId: freeAgent.id, targetTab: "mercado" },
    { title: "Aviso de seguridad de demo", body: "Las acciones de este mundo son simuladas y nunca escriben datos reales.", category: "security", mandatory: true, targetId: null, targetTab: "inicio" },
  ];
  return rows.map((row, index) => ({ ...row, createdAt: isoAtOffset(-index, 17, 15), id: `demo_notification_${pad(index + 1)}` }));
}

function storiesFor(
  matches: DemoWorldMatch[],
  teams: DemoWorldTeam[],
  players: DemoWorldPlayer[],
  achievements: DemoWorldAchievement[],
  challenges: DemoWorldChallenge[],
  attendance: DemoWorldAttendanceRecord[],
  rewardBoxes: DemoWorldRewardBox[],
  provincialRanking: DemoWorldProvincialRanking,
): DemoWorldStory[] {
  const completed = matches.filter((match) => match.scope === "challenge" && match.status === "finalized");
  const upcoming = matches.filter((match) => match.status === "scheduled");
  const counteredChallenge = challenges.find((challenge) => challenge.status === "countered")!;
  const rejectedChallenge = challenges.find((challenge) => challenge.status === "rejected")!;
  const featuredAchievement = achievements.find((achievement) => achievement.subjectId === DEMO_WORLD_PLAYER_PERSPECTIVE_ID && achievement.key === "player.all.hat_tricks.001")!;
  const featuredBox = rewardBoxes.find((box) => box.achievementId === featuredAchievement.id)!;
  const featuredAttendance = attendance.find((entry) => entry.playerId === DEMO_WORLD_PLAYER_PERSPECTIVE_ID && entry.status === "played")!;
  const freeAgent = players.find((player) => !player.teamId)!;
  const ownRank = provincialRanking.showcases["my-rank"];
  return [
    { id: "demo_story_001", type: "match", title: "Un 3-0 abrió el mapa de rivales", body: `${completed[0]!.homeLabel} logró su primera portería a cero ante ${completed[0]!.awayLabel}.`, date: completed[0]!.date, referenceIds: [completed[0]!.id, completed[0]!.homeTeamId, completed[0]!.awayTeamId!] },
    { id: "demo_story_002", type: "achievement", title: "Cobre para la primera victoria", body: "La recompensa aparece solo porque el resultado externo está confirmado.", date: achievements[0]!.occurredAt, referenceIds: [achievements[0]!.id, achievements[0]!.subjectId] },
    { id: "demo_story_003", type: "team", title: "Una plantilla que ya tiene memoria", body: `${teams[0]!.name} conserva más de cincuenta partidos y una identidad visual ganada.`, date: isoAtOffset(-20), referenceIds: [teams[0]!.id] },
    { id: "demo_story_004", type: "challenge", title: "La contrapropuesta evitó cancelar", body: "Dos equipos movieron la hora y mantuvieron el reto vivo.", date: counteredChallenge.date, referenceIds: [counteredChallenge.id, counteredChallenge.homeTeamId, counteredChallenge.awayTeamId] },
    { id: "demo_story_005", type: "market", title: "Un mediocentro busca grupo", body: `${freeAgent.name} aparece en Mercado sin revelar datos privados.`, date: isoAtOffset(-4), referenceIds: [freeAgent.id] },
    { id: "demo_story_006", type: "attendance", title: "Confirmó y estuvo en el campo", body: "La asistencia histórica distingue jugar de cancelar o no presentarse, sin convertir una baja normal en sanción.", date: featuredAttendance.recordedAt, referenceIds: [featuredAttendance.id, featuredAttendance.matchId, featuredAttendance.playerId] },
    { id: "demo_story_007", type: "team", title: "Girona entra en la red", body: `${teams[16]!.name} ya tiene rivales conocidos fuera de su municipio.`, date: isoAtOffset(-35), referenceIds: [teams[16]!.id] },
    { id: "demo_story_008", type: "achievement", title: "Los laureles exigen evidencia", body: "El hito de 25 partidos se muestra con el contador que lo respalda.", date: achievements.find((entry) => entry.key === "team.matches.025")!.occurredAt, referenceIds: [achievements.find((entry) => entry.key === "team.matches.025")!.id, teams[0]!.id] },
    { id: "demo_story_009", type: "challenge", title: "Un rechazo no rompe la agenda", body: "El historial conserva la propuesta y permite buscar otro rival.", date: rejectedChallenge.date, referenceIds: [rejectedChallenge.id, rejectedChallenge.homeTeamId, rejectedChallenge.awayTeamId] },
    { id: "demo_story_010", type: "market", title: "Partidos públicos con contexto", body: "Las plazas, modalidad y zona se ven antes de solicitar acceso.", date: upcoming[2]!.date, referenceIds: [upcoming[2]!.id] },
    { id: "demo_story_011", type: "reward", title: "Tres goles, una caja y una pieza nueva", body: "El hat-trick confirmado abre una caja local; la pieza aparece como NEW hasta equiparla en la ficha.", date: featuredAchievement.occurredAt, referenceIds: [featuredAchievement.id, featuredBox.id, featuredAchievement.subjectId] },
    { id: "demo_story_012", type: "ranking", title: "El #27 ya tiene contexto", body: `${ownRank.displayName} entra en el ranking provincial con ${ownRank.validChallenges} retos válidos y ${ownRank.logicalOpponents} rivales.`, date: provincialRanking.ranking.publication!.publishedAt, referenceIds: [DEMO_WORLD_PLAYER_PERSPECTIVE_ID, ownRank.entryKey!] },
  ];
}

function buildCore(
  teams: DemoWorldTeam[],
  players: DemoWorldPlayer[],
  matches: DemoWorldMatch[],
  achievements: DemoWorldAchievement[],
  challenges: DemoWorldChallenge[],
  attendance: DemoWorldAttendanceRecord[],
  rewardBoxes: DemoWorldRewardBox[],
  notifications: DemoWorldNotification[],
  provincialRanking: DemoWorldProvincialRanking,
): DemoWorldCoreChunk {
  const freeAgent = players.find((player) => !player.teamId)!;
  const previewPlayerIds = new Set([
    DEMO_WORLD_PLAYER_PERSPECTIVE_ID,
    DEMO_WORLD_ADMIN_PERSPECTIVE_ID,
    freeAgent.id,
    ...players.filter((player) => player.teamId === "demo_team_001").map((player) => player.id),
  ]);
  const previewMatches = [
    ...matches.filter((match) => match.status === "scheduled"),
    ...matches.filter((match) => match.status === "finalized" && (match.homeTeamId === "demo_team_001" || match.awayTeamId === "demo_team_001")).slice(0, 10),
  ];
  return {
    perspectives: [
      { id: "player", label: "Jugador del grupo", playerId: DEMO_WORLD_PLAYER_PERSPECTIVE_ID, role: "player", summary: "Ve su equipo, confirma asistencia y consulta su ficha.", teamId: "demo_team_001" },
      { id: "admin", label: "Admin del grupo", playerId: DEMO_WORLD_ADMIN_PERSPECTIVE_ID, role: "admin", summary: "Revisa alineación, solicitudes y configuración simulada.", teamId: "demo_team_001" },
      { id: "free-agent", label: "Jugador sin equipo", playerId: freeAgent.id, role: "visitor", summary: "Explora Mercado, partidos públicos y equipos retables.", teamId: null },
    ],
    preview: {
      matches: previewMatches,
      notifications,
      players: players.filter((player) => previewPlayerIds.has(player.id)),
    },
    provincialRanking,
    rankings: rankingsFor(teams),
    stories: storiesFor(matches, teams, players, achievements, challenges, attendance, rewardBoxes, provincialRanking),
    teams,
    venues,
  };
}

function updateTeamRankingLabels(teams: DemoWorldTeam[], rankings: DemoWorldRankingRow[]) {
  const byId = new Map(rankings.map((entry) => [entry.teamId, entry]));
  for (const team of teams) {
    const row = byId.get(team.id)!;
    team.rankingLabel = row.played < 2 ? "Ranking Demo · muestra corta" : `Ranking Demo · ${row.position}º`;
  }
}

function canonicalHash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export function generateDemoWorld(): DemoWorldSnapshot {
  const random = seededRandom(DEMO_WORLD_SEED);
  const teams = buildTeams();
  const players = buildPlayers(random, teams);
  const matches = buildMatches(random, teams, players);
  applyMatchStats(teams, players, matches);
  const attendance = attendanceFor(matches, players);
  const challenges = challengesFor(matches);
  const achievements = [...teamAchievements(teams), ...playerAchievements(players)];
  const rewardBoxes = rewardBoxesFor(achievements);
  const notifications = notificationsFor(matches, achievements, challenges, players);
  const provincialRanking = provincialRankingFor(players);
  const rankings = rankingsFor(teams);
  updateTeamRankingLabels(teams, rankings);

  const core = buildCore(teams, players, matches, achievements, challenges, attendance, rewardBoxes, notifications, provincialRanking);
  core.rankings = rankings;
  const playersChunk: DemoWorldPlayersChunk = { players };
  const matchesChunk: DemoWorldMatchesChunk = { attendance, challenges, matches };
  const activity: DemoWorldActivityChunk = {
    achievements,
    notifications,
    rewardBoxes,
    teamRewardMappings: DEMO_WORLD_TEAM_REWARD_MAPPINGS.map((entry) => ({ ...entry })),
  };
  const snapshotPayload = { activity, core, matches: matchesChunk, players: playersChunk };
  const hash = canonicalHash(snapshotPayload);
  const cacheKey = hash.slice(0, 16);
  const manifest: DemoWorldManifest = {
    chunks: {
      activity: `/demo-world/v1/activity.json?h=${cacheKey}`,
      core: `/demo-world/v1/core.json?h=${cacheKey}`,
      matches: `/demo-world/v1/matches.json?h=${cacheKey}`,
      players: `/demo-world/v1/players.json?h=${cacheKey}`,
    },
    counts: {
      achievements: achievements.length,
      challenges: challenges.length,
      matches: matches.length,
      notifications: activity.notifications.length,
      players: players.length,
      rewardBoxes: rewardBoxes.length,
      stories: core.stories.length,
      teams: teams.length,
    },
    demoNow: DEMO_WORLD_NOW,
    generatedAt: DEMO_WORLD_GENERATED_AT,
    hash,
    mode: DEMO_WORLD_MODE,
    season: DEMO_WORLD_SEASON,
    seed: DEMO_WORLD_SEED,
    version: DEMO_WORLD_VERSION,
  };
  return assertDemoWorldSnapshot({ activity, core, manifest, matches: matchesChunk, players: playersChunk });
}

async function writeSnapshot(snapshot: DemoWorldSnapshot, outputDirectory: string) {
  await mkdir(outputDirectory, { recursive: true });
  const files = {
    "activity.json": snapshot.activity,
    "core.json": snapshot.core,
    "manifest.json": snapshot.manifest,
    "matches.json": snapshot.matches,
    "players.json": snapshot.players,
  };
  for (const [name, value] of Object.entries(files)) {
    await writeFile(path.join(outputDirectory, name), `${JSON.stringify(value)}\n`, "utf8");
  }
}

async function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  const outputDirectory = path.join(root, "public/demo-world/v1");
  const snapshot = generateDemoWorld();
  await writeSnapshot(snapshot, outputDirectory);
  const bytes = Buffer.byteLength(JSON.stringify({ activity: snapshot.activity, core: snapshot.core, matches: snapshot.matches, players: snapshot.players }));
  process.stdout.write(`${JSON.stringify({ counts: snapshot.manifest.counts, hash: snapshot.manifest.hash, outputDirectory, payloadBytes: bytes }, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
