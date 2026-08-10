import { PLAYER_COSMETIC_MATERIALS } from "./player-cosmetics-catalog";
import type { PlayerCosmeticRarity } from "./player-cosmetics-contract";
import type { TeamShieldCosmeticSlot, TeamShieldRenderableItem } from "./team-shield-contract";

export type TeamShieldLabDecision = "MANTENER" | "REVISAR" | "DESCARTAR";

export type TeamShieldCatalogEntry = TeamShieldRenderableItem & {
  collection: "Base IQ" | "Fútbol de Barrio" | "Future IQ" | "Noche de Partido" | "Retro";
  decision: TeamShieldLabDecision;
  description: string;
  material: keyof typeof PLAYER_COSMETIC_MATERIALS | null;
  name: string;
  prototype: boolean;
  rarity: PlayerCosmeticRarity;
  slot: TeamShieldCosmeticSlot | null;
};

const base = (entry: Omit<TeamShieldCatalogEntry, "availability" | "collection" | "decision" | "prototype" | "rarity">): TeamShieldCatalogEntry => ({
  ...entry,
  availability: "base",
  collection: "Base IQ",
  decision: "MANTENER",
  prototype: false,
  rarity: "common",
});

export const TEAM_SHIELD_BASE_CATALOG: TeamShieldCatalogEntry[] = [
  base({ key: "team.shield.shape.classic_iq", name: "Clásico IQ", description: "Silueta principal de Pachangas IQ.", slot: "shape", material: null, render: { shape: "classic_iq" } }),
  base({ key: "team.shield.shape.round", name: "Redondo", description: "Emblema circular de lectura inmediata.", slot: "shape", material: null, render: { shape: "round" } }),
  base({ key: "team.shield.shape.tall", name: "Alto", description: "Escudo vertical de presencia competitiva.", slot: "shape", material: null, render: { shape: "tall" } }),
  base({ key: "team.shield.shape.swiss", name: "Suizo", description: "Hombros rectos y punta contenida.", slot: "shape", material: null, render: { shape: "swiss" } }),
  base({ key: "team.shield.shape.hex_iq", name: "Hex IQ", description: "Geometría técnica propia de Future IQ.", slot: "shape", material: null, render: { shape: "hex_iq" } }),
  base({ key: "team.shield.shape.diamond", name: "Diamante", description: "Silueta angular y ligera.", slot: "shape", material: null, render: { shape: "diamond" } }),
  base({ key: "team.shield.shape.modern", name: "Modern Crest", description: "Curvas tensas y base moderna.", slot: "shape", material: null, render: { shape: "modern" } }),
  base({ key: "team.shield.shape.barrio", name: "Barrio Shield", description: "Escudo robusto de fútbol de barrio.", slot: "shape", material: null, render: { shape: "barrio" } }),
  base({ key: "team.shield.color.midnight", name: "Midnight", description: "Azul noche profundo.", slot: null, material: "navy", render: { hex: "#071b31" } }),
  base({ key: "team.shield.color.cyan", name: "Cian IQ", description: "Acento tecnológico de Pachangas IQ.", slot: null, material: "cyan_iq", render: { hex: "#33d6dd" } }),
  base({ key: "team.shield.color.ivory", name: "Marfil", description: "Blanco cálido de alta lectura.", slot: null, material: "pearl", render: { hex: "#f1f4ea" } }),
  base({ key: "team.shield.color.crimson", name: "Carmesí", description: "Rojo deportivo contenido.", slot: null, material: null, render: { hex: "#b52838" } }),
  base({ key: "team.shield.color.emerald", name: "Esmeralda", description: "Verde de campo profundo.", slot: null, material: null, render: { hex: "#08765d" } }),
  base({ key: "team.shield.color.amber", name: "Ámbar", description: "Amarillo cálido competitivo.", slot: null, material: null, render: { hex: "#efb82e" } }),
  base({ key: "team.shield.background.duotone", name: "Dúo", description: "Base de dos tonos equilibrada.", slot: "background", material: null, render: { background: "duotone" } }),
  base({ key: "team.shield.background.solid", name: "Liso", description: "Color principal limpio.", slot: "background", material: null, render: { background: "solid" } }),
  base({ key: "team.shield.background.split", name: "Partido", description: "Dos campos verticales.", slot: "background", material: null, render: { background: "split" } }),
  base({ key: "team.shield.pattern.none", name: "Sin trama", description: "Superficie limpia.", slot: "pattern", material: null, render: { pattern: "none" } }),
  base({ key: "team.shield.pattern.diagonal", name: "Diagonal", description: "Franja diagonal deportiva.", slot: "pattern", material: null, render: { pattern: "diagonal" } }),
  base({ key: "team.shield.pattern.stripes", name: "Franjas", description: "Franjas verticales compactas.", slot: "pattern", material: null, render: { pattern: "stripes" } }),
  base({ key: "team.shield.pattern.chevron", name: "Chevron", description: "V central con profundidad.", slot: "pattern", material: null, render: { pattern: "chevron" } }),
  base({ key: "team.shield.symbol.ball_iq", name: "Balón IQ", description: "Balón geométrico propio.", slot: "primary_symbol", material: null, render: { symbol: "ball_iq" } }),
  base({ key: "team.shield.symbol.monogram", name: "Monograma", description: "Inicial central como símbolo.", slot: "primary_symbol", material: null, render: { symbol: "monogram" } }),
  base({ key: "team.shield.symbol.star_iq", name: "Estrella IQ", description: "Estrella técnica de ocho puntas.", slot: "primary_symbol", material: null, render: { symbol: "star_iq" } }),
  base({ key: "team.shield.symbol.bolt", name: "Rayo", description: "Rayo angular de energía.", slot: "primary_symbol", material: null, render: { symbol: "bolt" } }),
  base({ key: "team.shield.symbol.tower", name: "Torre", description: "Torre geométrica de barrio.", slot: "primary_symbol", material: null, render: { symbol: "tower" } }),
  base({ key: "team.shield.border.clean", name: "Contorno IQ", description: "Doble línea limpia de alto contraste.", slot: "border", material: "pearl", render: { border: "clean", material: "pearl" } }),
  base({ key: "team.shield.border.double", name: "Doble", description: "Marco doble deportivo.", slot: "border", material: "steel", render: { border: "double", material: "steel" } }),
];

const proposal = (entry: Omit<TeamShieldCatalogEntry, "availability" | "prototype"> & { prototype?: boolean }): TeamShieldCatalogEntry => ({
  ...entry,
  availability: entry.prototype ? "prototype" : "achievement",
  prototype: entry.prototype ?? false,
});

export const TEAM_SHIELD_COSMETIC_PROTOTYPES: TeamShieldCatalogEntry[] = [
  proposal({ key: "team.shield.border.steel", name: "Acero", description: "Acero cepillado sobrio.", collection: "Fútbol de Barrio", slot: "border", rarity: "common", material: "steel", render: { border: "material", material: "steel" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.border.bronze", name: "Bronce", description: "Bronce envejecido de tono deportivo.", collection: "Fútbol de Barrio", slot: "border", rarity: "uncommon", material: "bronze", render: { border: "material", material: "bronze" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.border.copper", name: "Cobre", description: "Cobre cálido con contraste alto.", collection: "Fútbol de Barrio", slot: "border", rarity: "uncommon", material: "copper", render: { border: "material", material: "copper" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.border.silver", name: "Plata", description: "Plata satinada de alta lectura.", collection: "Retro", slot: "border", rarity: "rare", material: "silver", render: { border: "material", material: "silver" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.border.gold", name: "Oro", description: "Oro contenido para hitos de élite.", collection: "Noche de Partido", slot: "border", rarity: "legendary", material: "gold", render: { border: "material", material: "gold" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.border.navy", name: "Navy", description: "Marco técnico azul oscuro.", collection: "Future IQ", slot: "border", rarity: "epic", material: "navy", render: { border: "material", material: "navy" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.border.carbon", name: "Carbono", description: "Carbono mate de baja reflexión.", collection: "Future IQ", slot: "border", rarity: "epic", material: "carbon", render: { border: "material", material: "carbon" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.border.black_matte", name: "Negro Mate", description: "Contorno oscuro táctico.", collection: "Noche de Partido", slot: "border", rarity: "rare", material: "black_matte", render: { border: "material", material: "black_matte" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.border.chrome", name: "Cromo", description: "Cromo especular para tamaños grandes.", collection: "Retro", slot: "border", rarity: "legendary", material: "chrome", render: { border: "material", material: "chrome" }, decision: "REVISAR", prototype: true }),
  proposal({ key: "team.shield.border.pearl", name: "Perla", description: "Marfil nacarado de colección.", collection: "Retro", slot: "border", rarity: "rare", material: "pearl", render: { border: "material", material: "pearl" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.pattern.grid_iq", name: "Grid IQ", description: "Retícula táctica discreta.", collection: "Future IQ", slot: "pattern", rarity: "uncommon", material: "navy", render: { pattern: "grid_iq" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.pattern.retro", name: "Retro", description: "Franjas estrechas clásicas.", collection: "Retro", slot: "pattern", rarity: "rare", material: null, render: { pattern: "retro" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.pattern.chalk", name: "Pizarra", description: "Trazos tácticos sobre negro mate.", collection: "Fútbol de Barrio", slot: "pattern", rarity: "rare", material: "black_matte", render: { pattern: "chalk" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.pattern.honeycomb", name: "Hex Mesh", description: "Malla hexagonal de competición.", collection: "Future IQ", slot: "pattern", rarity: "epic", material: "carbon", render: { pattern: "honeycomb" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.symbol.tower_elite", name: "Torre Elite", description: "Torre doble con placa inferior.", collection: "Fútbol de Barrio", slot: "primary_symbol", rarity: "uncommon", material: "steel", render: { symbol: "tower_elite" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.symbol.iq_star", name: "Estrella Future", description: "Estrella facetada de Future IQ.", collection: "Future IQ", slot: "primary_symbol", rarity: "rare", material: "cyan_iq", render: { symbol: "iq_star" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.symbol.crown_iq", name: "Corona IQ", description: "Corona geométrica compacta como símbolo central.", collection: "Noche de Partido", slot: "primary_symbol", rarity: "epic", material: "gold", render: { symbol: "crown_iq" }, decision: "REVISAR", prototype: true }),
  proposal({ key: "team.shield.symbol.nested_badge", name: "Escudo Interior", description: "Escudo dentro de escudo con lectura heráldica propia.", collection: "Retro", slot: "primary_symbol", rarity: "rare", material: "silver", render: { symbol: "nested_badge" }, decision: "REVISAR", prototype: true }),
  proposal({ key: "team.shield.symbol.orbit_ball", name: "Órbita IQ", description: "Balón abstracto de lenguaje Future IQ.", collection: "Future IQ", slot: "primary_symbol", rarity: "epic", material: "cyan_iq", render: { symbol: "orbit_ball" }, decision: "REVISAR", prototype: true }),
  proposal({ key: "team.shield.symbol.twin_bolt", name: "Doble Rayo", description: "Dos rayos enfrentados.", collection: "Noche de Partido", slot: "secondary_symbol", rarity: "rare", material: "gold", render: { symbol: "twin_bolt" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.ornament.crown", name: "Corona Geométrica", description: "Corona superior de líneas limpias.", collection: "Noche de Partido", slot: "top_ornament", rarity: "epic", material: "gold", render: { ornament: "crown", anchor: "top" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.ornament.three_stars", name: "Tres Estrellas", description: "Tres estrellas compactas.", collection: "Retro", slot: "top_ornament", rarity: "rare", material: "silver", render: { ornament: "three_stars", anchor: "top" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.ornament.laurels", name: "Laureles", description: "Laureles laterales de competición.", collection: "Retro", slot: "side_ornament", rarity: "rare", material: "silver", render: { ornament: "laurels", anchor: "sides" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.ornament.wings", name: "Alas", description: "Alas laterales tensas.", collection: "Future IQ", slot: "side_ornament", rarity: "epic", material: "silver", render: { ornament: "wings", anchor: "sides" }, decision: "REVISAR", prototype: true }),
  proposal({ key: "team.shield.ornament.side_bolts", name: "Rayos Laterales", description: "Rayos anclados a ambos lados.", collection: "Noche de Partido", slot: "side_ornament", rarity: "epic", material: "gold", render: { ornament: "side_bolts", anchor: "sides" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.ornament.banner", name: "Banner", description: "Cinta inferior de identidad.", collection: "Fútbol de Barrio", slot: "bottom_ornament", rarity: "uncommon", material: "copper", render: { ornament: "banner", anchor: "bottom" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.ornament.plate", name: "Placa", description: "Placa inferior metálica.", collection: "Future IQ", slot: "bottom_ornament", rarity: "rare", material: "navy", render: { ornament: "plate", anchor: "bottom" }, decision: "REVISAR" }),
  proposal({ key: "team.shield.effect.glint", name: "Glint", description: "Reflejo diagonal contenido.", collection: "Noche de Partido", slot: "effect", rarity: "legendary", material: "gold", render: { effect: "glint" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.effect.scan", name: "Scan", description: "Línea cian que recorre el escudo.", collection: "Future IQ", slot: "effect", rarity: "epic", material: "cyan_iq", render: { effect: "scan" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.effect.edge_glow", name: "Edge Glow", description: "Resplandor limitado al contorno.", collection: "Future IQ", slot: "effect", rarity: "rare", material: "cyan_iq", render: { effect: "edge_glow" }, decision: "MANTENER" }),
  proposal({ key: "team.shield.effect.holo", name: "Holo", description: "Cambio cromático sutil.", collection: "Future IQ", slot: "effect", rarity: "epic", material: "cyan_iq", render: { effect: "holo" }, decision: "REVISAR", prototype: true }),
];

export const TEAM_SHIELD_COSMETIC_V1_CANDIDATES = TEAM_SHIELD_COSMETIC_PROTOTYPES.filter(
  (item) => !item.prototype && item.decision === "MANTENER",
);

export const TEAM_SHIELD_RENDER_CATALOG = [
  ...TEAM_SHIELD_BASE_CATALOG,
  ...TEAM_SHIELD_COSMETIC_PROTOTYPES,
];

export function teamShieldCatalogEntry(key: string | null | undefined) {
  return key ? TEAM_SHIELD_RENDER_CATALOG.find((entry) => entry.key === key) ?? null : null;
}
