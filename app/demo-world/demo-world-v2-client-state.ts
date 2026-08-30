import {
  assertDemoWorldV2Snapshot,
  type DemoWorldV2ClubsRefereesChunk,
  type DemoWorldV2CompetitionChunk,
  type DemoWorldV2ConfigurationChunk,
  type DemoWorldV2Manifest,
  type DemoWorldV2OrganizerBillingChunk,
  type DemoWorldV2PrimaryTab,
  type DemoWorldV2PublicCompetitionsChunk,
  type DemoWorldV2Snapshot,
  type DemoWorldV2TournamentChunk,
  type DemoWorldV31TeamOperationalChunk,
  type DemoWorldV3OrganizerAccessChunk,
} from "./demo-world-v2-contract";
import type {
  DemoWorldActivityChunk,
  DemoWorldCoreChunk,
  DemoWorldMatchesChunk,
  DemoWorldPlayersChunk,
} from "./demo-world-contract";

const tabs: DemoWorldV2PrimaryTab[] = [
  "inicio",
  "partido",
  "mercado",
  "equipo",
  "perfil",
  "liga",
  "clasificacion",
  "configuracion",
  "jornadas",
  "estado-equipo",
  "competiciones",
  "club",
  "arbitros",
  "disciplina",
  "torneo",
  "planes",
];

async function loadChunk<T>(path: string): Promise<T> {
  const response = await fetch(path, {
    cache: "force-cache",
    credentials: "same-origin",
    method: "GET",
  });
  if (!response.ok) throw new Error(`No se pudo cargar el Mundo Demo V2 (${response.status}).`);
  return response.json() as Promise<T>;
}

export function demoWorldV2TabFromSearch(search: string): DemoWorldV2PrimaryTab {
  const value = new URLSearchParams(search).get("tab") as DemoWorldV2PrimaryTab | null;
  return value && tabs.includes(value) ? value : "inicio";
}

export function loadDemoWorldV2Core(manifest: DemoWorldV2Manifest) {
  return loadChunk<DemoWorldCoreChunk>(manifest.chunks.core);
}

export async function loadDemoWorldV2Snapshot(
  manifest: DemoWorldV2Manifest,
  loadedCore?: DemoWorldCoreChunk,
): Promise<DemoWorldV2Snapshot> {
  const [activity, clubsReferees, competitions, configuration, core, matches, organizerAccess, organizerBilling, players, publicCompetitions, teamOperational, tournament] = await Promise.all([
    loadChunk<DemoWorldActivityChunk>(manifest.chunks.activity),
    loadChunk<DemoWorldV2ClubsRefereesChunk>(manifest.chunks.clubsReferees),
    loadChunk<DemoWorldV2CompetitionChunk>(manifest.chunks.competitions),
    loadChunk<DemoWorldV2ConfigurationChunk>(manifest.chunks.configuration),
    loadedCore ? Promise.resolve(loadedCore) : loadDemoWorldV2Core(manifest),
    loadChunk<DemoWorldMatchesChunk>(manifest.chunks.matches),
    loadChunk<DemoWorldV3OrganizerAccessChunk>(manifest.chunks.organizerAccess),
    loadChunk<DemoWorldV2OrganizerBillingChunk>(manifest.chunks.organizerBilling),
    loadChunk<DemoWorldPlayersChunk>(manifest.chunks.players),
    loadChunk<DemoWorldV2PublicCompetitionsChunk>(manifest.chunks.publicCompetitions),
    loadChunk<DemoWorldV31TeamOperationalChunk>(manifest.chunks.teamOperational),
    loadChunk<DemoWorldV2TournamentChunk>(manifest.chunks.tournament),
  ]);
  return assertDemoWorldV2Snapshot({ activity, clubsReferees, competitions, configuration, core, manifest, matches, organizerAccess, organizerBilling, players, publicCompetitions, teamOperational, tournament });
}
