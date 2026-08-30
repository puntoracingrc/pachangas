import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { DemoWorldPlayer, DemoWorldTeam } from "../../app/demo-world/demo-world-contract";
import {
  DEMO_WORLD_V32_SEED,
  DEMO_WORLD_V32_VERSION,
  syntheticSeasonIntegrityErrors,
  syntheticSeasonPrivacyFindings,
  type DemoWorldV32Manifest,
  type DemoWorldV32Snapshot,
} from "../../app/demo-world/demo-world-v3-2-contract";
import { assertDemoWorldV2Snapshot } from "../../app/demo-world/demo-world-v2-contract";
import {
  buildSyntheticSeason,
  syntheticSeasonHash,
  SYNTHETIC_SEASON_DEMO_NOW,
  SYNTHETIC_SEASON_GENERATED_AT,
} from "../../simulation/synthetic-season/engine";
import { syntheticSeasonOracleReport } from "../../simulation/synthetic-season/oracles";
import { generateDemoWorldV2 } from "./generate-demo-world-v2";

function cloneTeam(template: DemoWorldTeam, id: string, name: string, publicLocation: string, territory: string): DemoWorldTeam {
  return {
    ...structuredClone(template),
    id,
    identity: "Plantilla ficticia de la temporada sintética, preparada para competir sin datos reales.",
    memberCount: 15,
    name,
    publicLocation,
    rankingLabel: "Temporada sintética 2026/27",
    territory,
  };
}

function clonePlayer(template: DemoWorldPlayer, id: string, name: string, teamId: string, ordinal: number): DemoWorldPlayer {
  return {
    ...structuredClone(template),
    appearances: 0,
    assists: 0,
    avatarHue: ordinal * 37 % 360,
    birthYear: 1982 + ordinal % 19,
    featuredAchievementKey: null,
    goals: 0,
    id,
    market: {
      availability: "Disponibilidad ficticia de temporada",
      modalities: ordinal % 3 === 0 ? ["sala", "futbol7"] : ["futbol7"],
      openToGuest: ordinal % 9 === 0,
      publicBio: "Perfil completamente ficticio para recorrer Mundo Demo.",
      zones: ["Zona Demo"],
    },
    name,
    teamId,
    wins: 0,
  };
}

function extendDemoRoster(snapshot: ReturnType<typeof generateDemoWorldV2>) {
  const core = structuredClone(snapshot.core);
  const players = structuredClone(snapshot.players);
  core.teams = core.teams.map((team) => ({ ...team, memberCount: 15 }));
  core.teams.push(
    cloneTeam(core.teams[28]!, "demo_team_031", "Far Montcada", "Montcada · Centre", "Vallès"),
    cloneTeam(core.teams[29]!, "demo_team_032", "Pont Vic", "Vic · Centre", "Osona"),
  );

  const templates = players.players.filter(({ teamId }) => teamId);
  let nextId = players.players.length + 1;
  for (let teamIndex = 0; teamIndex < 30; teamIndex += 1) {
    for (let addition = 0; addition < 4; addition += 1) {
      const ordinal = nextId;
      players.players.push(clonePlayer(
        templates[(teamIndex * 4 + addition) % templates.length]!,
        `demo_player_${String(nextId++).padStart(3, "0")}`,
        `Jugador Demo ${String(ordinal).padStart(3, "0")}`,
        `demo_team_${String(teamIndex + 1).padStart(3, "0")}`,
        ordinal,
      ));
    }
  }
  for (let teamIndex = 30; teamIndex < 32; teamIndex += 1) {
    for (let rosterIndex = 0; rosterIndex < 15; rosterIndex += 1) {
      const ordinal = nextId;
      players.players.push(clonePlayer(
        templates[(teamIndex * 15 + rosterIndex) % templates.length]!,
        `demo_player_${String(nextId++).padStart(3, "0")}`,
        `Jugador Demo ${String(ordinal).padStart(3, "0")}`,
        `demo_team_${String(teamIndex + 1).padStart(3, "0")}`,
        ordinal,
      ));
    }
  }
  core.perspectives.push(
    { id: "team-owner", label: "Owner de equipo", playerId: "demo_player_002", role: "admin", summary: "Revisa continuidad y estado operativo sin alterar el snapshot.", teamId: "demo_team_001" },
    { id: "club-organizer", label: "Organizador de Club", playerId: "demo_player_003", role: "admin", summary: "Consulta Clubs, inscripciones y competiciones ficticias.", teamId: "demo_team_003" },
    { id: "tournament-organizer", label: "Organizador de Torneo", playerId: "demo_player_004", role: "admin", summary: "Recorre grupos, cuadro y final canónicos.", teamId: "demo_team_004" },
    { id: "referee", label: "Árbitro", playerId: "demo_player_005", role: "player", summary: "Consulta asignaciones y disciplina pública saneada.", teamId: "demo_team_005" },
    { id: "platform-reviewer", label: "Platform reviewer", playerId: "demo_player_007", role: "admin", summary: "Inspecciona invariantes y estados sintéticos.", teamId: "demo_team_007" },
  );
  return { core, players };
}

export function generateDemoWorldV32(): {
  checkpoints: ReturnType<typeof buildSyntheticSeason>["checkpoints"];
  disciplineEvents: ReturnType<typeof buildSyntheticSeason>["disciplineEvents"];
  sanctions: ReturnType<typeof buildSyntheticSeason>["sanctions"];
  snapshot: DemoWorldV32Snapshot;
} {
  const legacy = generateDemoWorldV2();
  const extended = extendDemoRoster(legacy);
  assertDemoWorldV2Snapshot({ ...legacy, ...extended });
  const season = buildSyntheticSeason();
  const oracle = syntheticSeasonOracleReport({
    checkpoints: season.checkpoints,
    disciplineEvents: season.disciplineEvents,
    index: season.index,
    sanctions: season.sanctions,
  });
  if (!oracle.passed) throw new Error(`Synthetic season oracle failed:\n${oracle.errors.join("\n")}`);
  const integrityErrors = syntheticSeasonIntegrityErrors(season.index, season.checkpoints);
  if (integrityErrors.length) throw new Error(`Synthetic season integrity failed:\n${integrityErrors.join("\n")}`);

  const basePath = "/demo-world/v3-2";
  const cacheKey = season.index.proof.publicSnapshotHash.slice(0, 16);
  const payload = {
    activity: legacy.activity,
    clubsReferees: legacy.clubsReferees,
    competitions: legacy.competitions,
    configuration: legacy.configuration,
    core: extended.core,
    matches: legacy.matches,
    organizerAccess: legacy.organizerAccess,
    organizerBilling: legacy.organizerBilling,
    players: extended.players,
    publicCompetitions: legacy.publicCompetitions,
    season: season.index,
    teamOperational: legacy.teamOperational,
    tournament: legacy.tournament,
  };
  const manifest: DemoWorldV32Manifest = {
    checkpoints: season.index.checkpointFiles,
    chunks: {
      activity: `${basePath}/activity.json?h=${cacheKey}`,
      clubsReferees: `${basePath}/clubs-referees.json?h=${cacheKey}`,
      competitions: `${basePath}/competitions.json?h=${cacheKey}`,
      configuration: `${basePath}/configuration.json?h=${cacheKey}`,
      core: `${basePath}/core.json?h=${cacheKey}`,
      matches: `${basePath}/matches.json?h=${cacheKey}`,
      organizerAccess: `${basePath}/organizer-access.json?h=${cacheKey}`,
      organizerBilling: `${basePath}/organizer-billing.json?h=${cacheKey}`,
      players: `${basePath}/players.json?h=${cacheKey}`,
      publicCompetitions: `${basePath}/public-competitions.json?h=${cacheKey}`,
      season: `${basePath}/season.json?h=${cacheKey}`,
      teamOperational: `${basePath}/team-operational.json?h=${cacheKey}`,
      tournament: `${basePath}/tournament.json?h=${cacheKey}`,
    },
    counts: {
      ...legacy.manifest.counts,
      canonicalMatches: 128,
      checkpoints: 9,
      clubs: 6,
      competitions: 4,
      matches: 128,
      players: 481,
      referees: 12,
      rounds: 32,
      teams: 32,
      tournaments: 2,
    },
    demoNow: SYNTHETIC_SEASON_DEMO_NOW,
    generatedAt: SYNTHETIC_SEASON_GENERATED_AT,
    hash: syntheticSeasonHash(payload),
    mode: "demo-world-read-only",
    season: "2026/27",
    seed: DEMO_WORLD_V32_SEED,
    version: DEMO_WORLD_V32_VERSION,
  } as DemoWorldV32Manifest;
  const snapshot: DemoWorldV32Snapshot = { ...payload, manifest };
  const privacyFindings = syntheticSeasonPrivacyFindings(JSON.stringify(snapshot));
  if (privacyFindings.length) throw new Error(`DEMO_WORLD_V32_PRIVACY_SCAN_FAILED:${privacyFindings.join(",")}`);
  return { checkpoints: season.checkpoints, disciplineEvents: season.disciplineEvents, sanctions: season.sanctions, snapshot };
}

async function writeJson(file: string, value: unknown) {
  await writeFile(file, `${JSON.stringify(value)}\n`, "utf8");
}

export async function writeDemoWorldV32(root: string) {
  const outputDirectory = path.join(root, "public/demo-world/v3-2");
  const generatedDirectory = path.join(root, "simulation/synthetic-season/generated");
  const checkpointDirectory = path.join(outputDirectory, "checkpoints");
  await mkdir(checkpointDirectory, { recursive: true });
  await mkdir(generatedDirectory, { recursive: true });
  const { checkpoints, snapshot } = generateDemoWorldV32();
  const files: Record<string, unknown> = {
    "activity.json": snapshot.activity,
    "clubs-referees.json": snapshot.clubsReferees,
    "competitions.json": snapshot.competitions,
    "configuration.json": snapshot.configuration,
    "core.json": snapshot.core,
    "manifest.json": snapshot.manifest,
    "matches.json": snapshot.matches,
    "organizer-access.json": snapshot.organizerAccess,
    "organizer-billing.json": snapshot.organizerBilling,
    "players.json": snapshot.players,
    "public-competitions.json": snapshot.publicCompetitions,
    "season.json": snapshot.season,
    "team-operational.json": snapshot.teamOperational,
    "tournament.json": snapshot.tournament,
  };
  await Promise.all(Object.entries(files).map(([name, value]) => writeJson(path.join(outputDirectory, name), value)));
  await Promise.all(checkpoints.map((checkpoint) => writeJson(path.join(checkpointDirectory, `checkpoint-${checkpoint.checkpoint}.json`), checkpoint)));
  await writeJson(path.join(generatedDirectory, "synthetic-season-proof.json"), snapshot.season.proof);
  return {
    authorityHash: snapshot.season.proof.authorityHash,
    counts: snapshot.season.proof.counts,
    outputDirectory,
    publicSnapshotHash: snapshot.season.proof.publicSnapshotHash,
  };
}

async function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  process.stdout.write(`${JSON.stringify(await writeDemoWorldV32(root), null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
