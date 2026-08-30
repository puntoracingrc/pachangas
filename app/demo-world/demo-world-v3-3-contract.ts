import type { DemoWorldPerspectiveId } from "./demo-world-contract";
import type { DemoWorldV2PrimaryTab } from "./demo-world-v2-contract";
import type {
  DemoWorldV32Manifest,
  DemoWorldV32Snapshot,
  SyntheticSeasonCheckpointId,
  SyntheticSeasonSurface,
} from "./demo-world-v3-2-contract";

export const DEMO_WORLD_V33_VERSION = 3.3 as const;
export const DEMO_WORLD_V33_AUTHORITY_VERSION = 3.2 as const;
export const DEMO_WORLD_V33_AUTHORITY_HASH = "763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1" as const;

export type DemoWorldV33TourId =
  | "player-match"
  | "team-admin"
  | "free-agent"
  | "league-organizer"
  | "tournament-organizer"
  | "referee"
  | "club-organizer"
  | "platform-review";

export type DemoWorldV33TourStep = {
  checkpoint?: SyntheticSeasonCheckpointId;
  competition?: string;
  comparison: string;
  description: string;
  id: string;
  perspective: DemoWorldPerspectiveId;
  surface?: SyntheticSeasonSurface;
  tab: DemoWorldV2PrimaryTab;
  title: string;
  week?: number;
};

export type DemoWorldV33Tour = {
  description: string;
  id: DemoWorldV33TourId;
  label: string;
  steps: DemoWorldV33TourStep[];
};

export type DemoWorldV33PresentationManifest = {
  authority: {
    hash: typeof DEMO_WORLD_V33_AUTHORITY_HASH;
    manifest: "/demo-world/v3-2/manifest.json";
    version: typeof DEMO_WORLD_V33_AUTHORITY_VERSION;
  };
  guidedReview: {
    localProgressOnly: true;
    remoteWrites: 0;
    tourCount: 8;
  };
  mode: "guided-product-review";
  privacy: {
    authIds: false;
    pii: false;
  };
  version: typeof DEMO_WORLD_V33_VERSION;
};

export type DemoWorldV33Manifest = Omit<DemoWorldV32Manifest, "version"> & {
  presentation: DemoWorldV33PresentationManifest;
  version: typeof DEMO_WORLD_V33_VERSION;
};

export type DemoWorldV33Snapshot = Omit<DemoWorldV32Snapshot, "manifest"> & {
  manifest: DemoWorldV33Manifest;
};

export const DEMO_WORLD_V33_TOURS: DemoWorldV33Tour[] = [
  {
    description: "De la asistencia al resultado oficial, sin confundir intención local con confirmación.",
    id: "player-match",
    label: "Jugador · partido",
    steps: [
      { comparison: "Inicio oficial y Demo usan la misma prioridad.", description: "Revisa el siguiente paso del jugador.", id: "home", perspective: "player", tab: "inicio", title: "Tu siguiente acción" },
      { comparison: "La Demo conserva el flujo de Partido.", description: "Consulta convocatoria, alineación y resultado.", id: "match", perspective: "player", tab: "partido", title: "Partido completo" },
    ],
  },
  {
    description: "Operación diaria de equipo con permisos de owner y acciones administrativas separadas.",
    id: "team-admin",
    label: "Owner · equipo",
    steps: [
      { comparison: "El contexto reemplaza controles técnicos duplicados.", description: "Comprueba identidad, plantilla y rol.", id: "team", perspective: "team-owner", tab: "equipo", title: "Equipo activo" },
      { comparison: "Solo el rol habilitado ve configuración.", description: "Abre la configuración competitiva ficticia.", id: "config", perspective: "team-owner", tab: "configuracion", title: "Herramientas de gestión" },
    ],
  },
  {
    description: "Descubrimiento público para quien aún no pertenece a un equipo.",
    id: "free-agent",
    label: "Agente libre",
    steps: [
      { comparison: "Mercado real y Demo comparten jerarquía.", description: "Explora jugadores, equipos y partidos públicos.", id: "market", perspective: "free-agent", tab: "mercado", title: "Encontrar una oportunidad" },
      { comparison: "Solo se muestran datos públicos ficticios.", description: "Consulta competiciones públicas sin iniciar sesión.", id: "public", perspective: "free-agent", tab: "competiciones", title: "Competición pública" },
    ],
  },
  {
    description: "La temporada sintética explica jornadas, clasificación y excepciones.",
    id: "league-organizer",
    label: "Organizador · Liga",
    steps: [
      { checkpoint: 1, competition: "liga-barrios-iq", comparison: "El checkpoint es una proyección inmutable.", description: "Revisa inscripciones y preparación.", id: "setup", perspective: "league-organizer", surface: "leagues", tab: "temporada", title: "Preparar Liga", week: 1 },
      { checkpoint: 4, competition: "liga-barrios-iq", comparison: "Los resultados proceden del motor canónico.", description: "Compara clasificación a mitad de temporada.", id: "standings", perspective: "league-organizer", surface: "standings", tab: "temporada", title: "Clasificación viva", week: 8 },
    ],
  },
  {
    description: "Sorteo, grupos y cuadro final de un torneo ficticio completo.",
    id: "tournament-organizer",
    label: "Organizador · Torneo",
    steps: [
      { checkpoint: 3, competition: "copa-barrios-iq", comparison: "La Demo representa el sorteo sin recalcularlo.", description: "Inspecciona el arranque del torneo.", id: "groups", perspective: "tournament-organizer", surface: "tournaments", tab: "temporada", title: "Fase de grupos", week: 4 },
      { checkpoint: 8, competition: "copa-barrios-iq", comparison: "El cuadro conserva la progresión oficial.", description: "Llega hasta campeón y postemporada.", id: "bracket", perspective: "tournament-organizer", surface: "bracket", tab: "temporada", title: "Cuadro final", week: 16 },
    ],
  },
  {
    description: "Perfil y asignaciones arbitrales con acceso limitado al partido correspondiente.",
    id: "referee",
    label: "Árbitro",
    steps: [
      { comparison: "El rol arbitral recibe su propia navegación contextual.", description: "Consulta fichas y disponibilidad ficticias.", id: "directory", perspective: "referee", tab: "arbitros", title: "Red arbitral" },
      { checkpoint: 5, comparison: "Las asignaciones conservan su linaje canónico.", description: "Revisa asignaciones y sustituciones.", id: "assignments", perspective: "referee", surface: "referees", tab: "temporada", title: "Asignaciones" },
    ],
  },
  {
    description: "Identidad de Club y continuidad entre varios equipos.",
    id: "club-organizer",
    label: "Organizador · Club",
    steps: [
      { comparison: "El perfil público replica la superficie oficial.", description: "Revisa Club, equipos vinculados e identidad.", id: "club", perspective: "club-organizer", tab: "club", title: "Club público" },
      { comparison: "La facturación sigue separada del estado deportivo.", description: "Consulta planes sin checkout ni precios activos.", id: "plans", perspective: "club-organizer", tab: "planes", title: "Acceso organizador" },
    ],
  },
  {
    description: "Revisión transversal de estados, privacidad y continuidad deportiva.",
    id: "platform-review",
    label: "Revisor de plataforma",
    steps: [
      { checkpoint: 6, comparison: "La restricción no reescribe resultados ni Rating.", description: "Comprueba estados operativos y continuidad.", id: "states", perspective: "platform-reviewer", surface: "teams", tab: "temporada", title: "Estados de equipo" },
      { checkpoint: 8, comparison: "Incidencias y desempates mantienen evidencia.", description: "Revisa fallos inyectados y ganador canónico.", id: "incidents", perspective: "platform-reviewer", surface: "incidents", tab: "temporada", title: "Evidencia de autoridad" },
    ],
  },
];

export function demoWorldV33StepHref(tour: DemoWorldV33Tour, stepIndex: number) {
  const step = tour.steps[stepIndex] ?? tour.steps[0]!;
  const params = new URLSearchParams({
    perspective: step.perspective,
    step: String(stepIndex),
    tab: step.tab,
    tour: tour.id,
  });
  if (step.checkpoint !== undefined) params.set("checkpoint", String(step.checkpoint));
  if (step.week !== undefined) params.set("week", String(step.week));
  if (step.competition) params.set("competition", step.competition);
  if (step.surface) {
    params.set("surface", step.surface);
    params.set("view", step.surface);
  }
  return `/demo?${params.toString()}`;
}
