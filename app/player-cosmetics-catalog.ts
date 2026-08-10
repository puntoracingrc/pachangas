import type {
  PlayerCosmeticLoadout,
  PlayerCosmeticRarity,
  PlayerCosmeticRenderContract,
  PlayerCosmeticSlot,
} from "./player-cosmetics-contract";

export type PlayerCosmeticCatalogEntry = {
  collection: "Fútbol de Barrio" | "Future IQ" | "Noche de Partido" | "Retro";
  description: string;
  key: string;
  material: string | null;
  name: string;
  prototype: boolean;
  rarity: PlayerCosmeticRarity;
  render: PlayerCosmeticRenderContract;
  slot: PlayerCosmeticSlot;
};

export const PLAYER_COSMETIC_SLOT_LABELS: Record<PlayerCosmeticSlot, string> = {
  accent: "Acento",
  background: "Fondo",
  effect: "Efecto",
  frame: "Marco",
  title: "Título",
};

export const PLAYER_COSMETIC_RARITY_LABELS: Record<PlayerCosmeticRarity, string> = {
  common: "Común",
  uncommon: "Poco común",
  rare: "Raro",
  epic: "Épico",
  legendary: "Legendario",
};

export const PLAYER_COSMETIC_MATERIALS = {
  black_matte: { accent: "#69736f", base: "#111614", highlight: "#a4ada9" },
  bronze: { accent: "#704326", base: "#a6653e", highlight: "#e0a371" },
  carbon: { accent: "#202827", base: "#343e3b", highlight: "#82908b" },
  chrome: { accent: "#5d6770", base: "#d8dde0", highlight: "#ffffff" },
  copper: { accent: "#6e2f19", base: "#b96737", highlight: "#f0b17f" },
  cyan_iq: { accent: "#087987", base: "#00c6d8", highlight: "#bbfbff" },
  gold: { accent: "#8a6110", base: "#d6a928", highlight: "#fff0a8" },
  navy: { accent: "#07152e", base: "#173a67", highlight: "#5aa7ff" },
  pearl: { accent: "#b4c6c1", base: "#e9f0ec", highlight: "#ffffff" },
  silver: { accent: "#667078", base: "#aeb7bd", highlight: "#eef4f6" },
  steel: { accent: "#354349", base: "#71828a", highlight: "#c7d3d6" },
} as const;

const selected: PlayerCosmeticCatalogEntry[] = [
  { key: "player.frame.barrio.steel", name: "Barrio Acero", description: "Acero cepillado y remaches sobrios.", collection: "Fútbol de Barrio", slot: "frame", rarity: "common", material: "steel", render: { frameStyle: "barrio", material: "steel" }, prototype: false },
  { key: "player.frame.barrio.copper", name: "Marco Cobre", description: "Cobre cálido con desgaste de partido.", collection: "Fútbol de Barrio", slot: "frame", rarity: "uncommon", material: "copper", render: { frameStyle: "barrio", material: "copper" }, prototype: false },
  { key: "player.frame.barrio.silver", name: "Barrio Plata", description: "Plata satinada para una ficha limpia.", collection: "Fútbol de Barrio", slot: "frame", rarity: "rare", material: "silver", render: { frameStyle: "barrio", material: "silver" }, prototype: false },
  { key: "player.frame.future.navy", name: "Future IQ Navy", description: "Marco técnico de profundidad Navy.", collection: "Future IQ", slot: "frame", rarity: "epic", material: "navy", render: { frameStyle: "future", material: "navy" }, prototype: false },
  { key: "player.frame.retro.chrome", name: "Retro Cromo", description: "Cromo discreto inspirado en cartas clásicas.", collection: "Retro", slot: "frame", rarity: "legendary", material: "chrome", render: { frameStyle: "retro", material: "chrome" }, prototype: false },
  { key: "player.background.asphalt_night", name: "Asfalto Nocturno", description: "Textura oscura de pista de barrio.", collection: "Noche de Partido", slot: "background", rarity: "common", material: "black_matte", render: { backgroundStyle: "asphalt_night" }, prototype: false },
  { key: "player.background.grid_iq", name: "Grid IQ", description: "Retícula táctica tenue.", collection: "Future IQ", slot: "background", rarity: "uncommon", material: "navy", render: { backgroundStyle: "grid_iq" }, prototype: false },
  { key: "player.accent.copper", name: "Acento Cobre", description: "Líneas y barras de cobre.", collection: "Fútbol de Barrio", slot: "accent", rarity: "uncommon", material: "copper", render: { accent: "copper" }, prototype: false },
  { key: "player.accent.navy", name: "Acento Navy", description: "Contraste técnico Navy.", collection: "Future IQ", slot: "accent", rarity: "epic", material: "navy", render: { accent: "navy" }, prototype: false },
  { key: "player.effect.spotlights", name: "Focos", description: "Barrido suave de luz de estadio.", collection: "Noche de Partido", slot: "effect", rarity: "rare", material: null, render: { effect: "spotlights", intensity: "subtle" }, prototype: false },
  { key: "player.effect.iq_scan", name: "IQ Scan", description: "Escaneo horizontal cian.", collection: "Future IQ", slot: "effect", rarity: "epic", material: "cyan_iq", render: { effect: "scan", direction: "horizontal" }, prototype: false },
  { key: "player.effect.gold_glint", name: "Glint Oro", description: "Reflejo dorado diagonal.", collection: "Noche de Partido", slot: "effect", rarity: "legendary", material: "gold", render: { effect: "glint", direction: "diagonal" }, prototype: false },
  { key: "player.title.old_school", name: "De toda la vida", description: "Título para veteranos de la pachanga.", collection: "Fútbol de Barrio", slot: "title", rarity: "common", material: null, render: { title: "De toda la vida" }, prototype: false },
  { key: "player.title.team_engine", name: "Motor del equipo", description: "Título de constancia y equipo.", collection: "Noche de Partido", slot: "title", rarity: "rare", material: null, render: { title: "Motor del equipo" }, prototype: false },
];

const experimental: PlayerCosmeticCatalogEntry[] = [
  { key: "prototype.frame.barrio.bronze", name: "Barrio Bronce", description: "Bronce cálido de competición local.", collection: "Fútbol de Barrio", slot: "frame", rarity: "uncommon", material: "bronze", render: { frameStyle: "barrio", material: "bronze" }, prototype: true },
  { key: "prototype.frame.barrio.gold", name: "Barrio Oro", description: "Oro contenido para hitos de temporada.", collection: "Noche de Partido", slot: "frame", rarity: "legendary", material: "gold", render: { frameStyle: "barrio", material: "gold" }, prototype: true },
  { key: "prototype.frame.future.carbon", name: "Future Carbono", description: "Carbono técnico con brillo muy bajo.", collection: "Future IQ", slot: "frame", rarity: "epic", material: "carbon", render: { frameStyle: "future", material: "carbon" }, prototype: true },
  { key: "prototype.frame.barrio.black_matte", name: "Barrio Negro Mate", description: "Marco oscuro sin reflejos dominantes.", collection: "Noche de Partido", slot: "frame", rarity: "rare", material: "black_matte", render: { frameStyle: "barrio", material: "black_matte" }, prototype: true },
  { key: "prototype.frame.future.pearl", name: "Future Perla", description: "Perla clara de lectura limpia.", collection: "Future IQ", slot: "frame", rarity: "rare", material: "pearl", render: { frameStyle: "future", material: "pearl" }, prototype: true },
  { key: "prototype.background.paper_league", name: "Papel de Liga", description: "Papel impreso de competición.", collection: "Retro", slot: "background", rarity: "common", material: null, render: { backgroundStyle: "paper_league" }, prototype: true },
  { key: "prototype.background.chalkboard", name: "Pizarra de Míster", description: "Trazos tácticos sobre negro.", collection: "Fútbol de Barrio", slot: "background", rarity: "rare", material: "black_matte", render: { backgroundStyle: "chalkboard" }, prototype: true },
  { key: "prototype.background.floodlights", name: "Noche de Focos", description: "Grada y luz difusa.", collection: "Noche de Partido", slot: "background", rarity: "epic", material: "navy", render: { backgroundStyle: "floodlights" }, prototype: true },
  { key: "prototype.accent.silver", name: "Acento Plata", description: "Separadores plateados.", collection: "Retro", slot: "accent", rarity: "rare", material: "silver", render: { accent: "silver" }, prototype: true },
  { key: "prototype.accent.cyan", name: "Acento Cian", description: "Lectura cian de datos.", collection: "Future IQ", slot: "accent", rarity: "rare", material: "cyan_iq", render: { accent: "cyan_iq" }, prototype: true },
  { key: "prototype.accent.gold", name: "Acento Oro", description: "Detalle dorado puntual.", collection: "Noche de Partido", slot: "accent", rarity: "legendary", material: "gold", render: { accent: "gold" }, prototype: true },
  { key: "prototype.effect.scan_diagonal", name: "Scan Diagonal", description: "Lectura diagonal de baja intensidad.", collection: "Future IQ", slot: "effect", rarity: "rare", material: "cyan_iq", render: { effect: "scan", direction: "diagonal" }, prototype: true },
  { key: "prototype.effect.holo_shimmer", name: "Holo Suave", description: "Cambio holográfico sutil sin ocultar datos.", collection: "Future IQ", slot: "effect", rarity: "epic", material: "cyan_iq", render: { effect: "holo_shimmer", intensity: "subtle" }, prototype: true },
  { key: "prototype.effect.chrome_sweep", name: "Barrido Cromo", description: "Brillo frío sobre el borde.", collection: "Retro", slot: "effect", rarity: "epic", material: "chrome", render: { effect: "chrome_sweep" }, prototype: true },
  { key: "prototype.title.street_captain", name: "Capitán de barrio", description: "Título social de la pista.", collection: "Fútbol de Barrio", slot: "title", rarity: "rare", material: null, render: { title: "Capitán de barrio" }, prototype: true },
  { key: "prototype.title.night_shift", name: "Turno de noche", description: "Título de noches de partido.", collection: "Noche de Partido", slot: "title", rarity: "uncommon", material: null, render: { title: "Turno de noche" }, prototype: true },
];

export const PLAYER_COSMETIC_CATALOG = selected;
export const PLAYER_COSMETIC_PROTOTYPES = [...selected, ...experimental];

export function catalogEntry(key: string | null | undefined) {
  return key ? PLAYER_COSMETIC_PROTOTYPES.find((entry) => entry.key === key) ?? null : null;
}

export function titleForLoadout(loadout: PlayerCosmeticLoadout) {
  const entry = catalogEntry(loadout.titleKey);
  return typeof entry?.render.title === "string" ? entry.render.title : null;
}
