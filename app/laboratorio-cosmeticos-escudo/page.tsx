"use client";

import { useMemo, useState } from "react";
import {
  CosmeticCategoryNav,
  CosmeticEditorShell,
  CosmeticOptionSelector,
  EditorActions,
  UnsavedChanges,
} from "../_components/cosmetics-editor";
import { TeamShieldView } from "../_components/team-shield-view";
import {
  TEAM_SHIELD_BASE_CATALOG,
  TEAM_SHIELD_COSMETIC_PROTOTYPES,
  TEAM_SHIELD_COSMETIC_V1_CANDIDATES,
  TEAM_SHIELD_RENDER_CATALOG,
  type TeamShieldCatalogEntry,
} from "../team-shield-cosmetics-catalog";
import {
  TEAM_SHIELD_DEFAULT_CONFIG,
  teamShieldDesignEquals,
  type TeamShieldConfig,
  type TeamShieldCosmeticSlot,
} from "../team-shield-contract";
import styles from "./page.module.css";

const labels: Record<TeamShieldCosmeticSlot, string> = {
  background: "Fondo",
  border: "Borde",
  bottom_ornament: "Inferior",
  effect: "Efecto",
  pattern: "Patrón",
  primary_symbol: "Símbolo",
  secondary_symbol: "Símbolo 2",
  shape: "Forma",
  side_ornament: "Laterales",
  top_ornament: "Superior",
};

const tabs = (Object.keys(labels) as TeamShieldCosmeticSlot[]).map((key) => ({ key, label: labels[key] }));
const colors = TEAM_SHIELD_BASE_CATALOG.filter((item) => item.key.startsWith("team.shield.color."));

type ShieldSample = {
  config: TeamShieldConfig;
  density?: "LIMPIO" | "MEDIO" | "CARGADO";
  family?: string;
  label: string;
  note?: string;
};

function sampleConfig(overrides: Partial<TeamShieldConfig>): TeamShieldConfig {
  return { ...TEAM_SHIELD_DEFAULT_CONFIG, ...overrides };
}

const presets: Array<{ config: TeamShieldConfig; label: string }> = [
  {
    label: "Base IQ",
    config: { ...TEAM_SHIELD_DEFAULT_CONFIG },
  },
  {
    label: "Barrio",
    config: {
      ...TEAM_SHIELD_DEFAULT_CONFIG,
      borderKey: "team.shield.border.copper",
      bottomOrnamentKey: "team.shield.ornament.banner",
      initials: "RAV",
      patternKey: "team.shield.pattern.stripes",
      primaryColorKey: "team.shield.color.crimson",
      primarySymbolKey: "team.shield.symbol.tower_elite",
      secondaryColorKey: "team.shield.color.ivory",
      shapeKey: "team.shield.shape.barrio",
    },
  },
  {
    label: "Future IQ",
    config: {
      ...TEAM_SHIELD_DEFAULT_CONFIG,
      borderKey: "team.shield.border.navy",
      effectKey: "team.shield.effect.scan",
      initials: "IQ7",
      patternKey: "team.shield.pattern.grid_iq",
      primarySymbolKey: "team.shield.symbol.iq_star",
      shapeKey: "team.shield.shape.hex_iq",
    },
  },
  {
    label: "Noche",
    config: sampleConfig({
      borderKey: "team.shield.border.gold",
      effectKey: "team.shield.effect.glint",
      foundationYear: "2026",
      initials: "NOC",
      primaryColorKey: "team.shield.color.midnight",
      primarySymbolKey: "team.shield.symbol.bolt",
      secondaryColorKey: "team.shield.color.amber",
      shapeKey: "team.shield.shape.tall",
      topOrnamentKey: "team.shield.ornament.crown",
    }),
  },
  {
    label: "Retro",
    config: sampleConfig({
      borderKey: "team.shield.border.silver",
      foundationYear: "1986",
      initials: "CRT",
      patternKey: "team.shield.pattern.retro",
      primaryColorKey: "team.shield.color.emerald",
      primarySymbolKey: "team.shield.symbol.ball_iq",
      secondaryColorKey: "team.shield.color.ivory",
      shapeKey: "team.shield.shape.swiss",
      topOrnamentKey: "team.shield.ornament.three_stars",
    }),
  },
];

const familySamples: ShieldSample[] = [
  { label: "Base limpio", family: "Clásico", density: "LIMPIO", config: sampleConfig({ initials: "PIQ", patternKey: null }) },
  { label: "Clásico plata", family: "Clásico", density: "MEDIO", config: sampleConfig({ borderKey: "team.shield.border.silver", initials: "CLB", patternKey: "team.shield.pattern.stripes", primaryColorKey: "team.shield.color.crimson", secondaryColorKey: "team.shield.color.ivory", shapeKey: "team.shield.shape.round" }) },
  { label: "Clásico gala", family: "Clásico", density: "CARGADO", config: sampleConfig({ borderKey: "team.shield.border.gold", bottomOrnamentKey: "team.shield.ornament.banner", effectKey: "team.shield.effect.glint", initials: "G11", primaryColorKey: "team.shield.color.midnight", secondaryColorKey: "team.shield.color.amber", sideOrnamentKey: "team.shield.ornament.laurels", topOrnamentKey: "team.shield.ornament.crown" }) },
  { label: "Torre de barrio", family: "Barrio", density: "MEDIO", config: presets[1].config },
  { label: "Pizarra local", family: "Barrio", density: "LIMPIO", config: sampleConfig({ borderKey: "team.shield.border.black_matte", initials: "SUR", patternKey: "team.shield.pattern.chalk", primaryColorKey: "team.shield.color.midnight", primarySymbolKey: "team.shield.symbol.monogram", secondaryColorKey: "team.shield.color.amber", shapeKey: "team.shield.shape.barrio" }) },
  { label: "Barrio laureado", family: "Barrio", density: "CARGADO", config: sampleConfig({ borderKey: "team.shield.border.bronze", bottomOrnamentKey: "team.shield.ornament.banner", foundationYear: "2004", initials: "BCN", patternKey: "team.shield.pattern.stripes", primaryColorKey: "team.shield.color.crimson", primarySymbolKey: "team.shield.symbol.tower", secondaryColorKey: "team.shield.color.ivory", sideOrnamentKey: "team.shield.ornament.laurels", topOrnamentKey: "team.shield.ornament.three_stars" }) },
  { label: "Future Scan", family: "Future IQ", density: "MEDIO", config: presets[2].config },
  { label: "Órbita Carbono", family: "Future IQ", density: "LIMPIO", config: sampleConfig({ borderKey: "team.shield.border.carbon", effectKey: "team.shield.effect.edge_glow", initials: "FX", patternKey: "team.shield.pattern.honeycomb", primaryColorKey: "team.shield.color.midnight", primarySymbolKey: "team.shield.symbol.orbit_ball", secondaryColorKey: "team.shield.color.cyan", shapeKey: "team.shield.shape.modern" }) },
  { label: "Future Holo", family: "Future IQ", density: "CARGADO", config: sampleConfig({ borderKey: "team.shield.border.chrome", bottomOrnamentKey: "team.shield.ornament.plate", effectKey: "team.shield.effect.holo", initials: "IQX", patternKey: "team.shield.pattern.grid_iq", primaryColorKey: "team.shield.color.midnight", primarySymbolKey: "team.shield.symbol.nested_badge", secondaryColorKey: "team.shield.color.cyan", shapeKey: "team.shield.shape.hex_iq", sideOrnamentKey: "team.shield.ornament.wings" }) },
  { label: "Noche Glint", family: "Noche", density: "MEDIO", config: presets[3].config },
  { label: "Noche Mate", family: "Noche", density: "LIMPIO", config: sampleConfig({ borderKey: "team.shield.border.black_matte", effectKey: "team.shield.effect.edge_glow", initials: "N8", patternKey: null, primaryColorKey: "team.shield.color.midnight", primarySymbolKey: "team.shield.symbol.bolt", secondaryColorKey: "team.shield.color.crimson", shapeKey: "team.shield.shape.diamond" }) },
  { label: "Noche eléctrica", family: "Noche", density: "CARGADO", config: sampleConfig({ borderKey: "team.shield.border.gold", effectKey: "team.shield.effect.glint", initials: "RAY", patternKey: "team.shield.pattern.chevron", primaryColorKey: "team.shield.color.midnight", primarySymbolKey: "team.shield.symbol.twin_bolt", secondaryColorKey: "team.shield.color.amber", shapeKey: "team.shield.shape.tall", sideOrnamentKey: "team.shield.ornament.side_bolts", topOrnamentKey: "team.shield.ornament.crown" }) },
  { label: "Retro 1986", family: "Retro", density: "MEDIO", config: presets[4].config },
  { label: "Retro Cromo", family: "Retro", density: "LIMPIO", config: sampleConfig({ borderKey: "team.shield.border.chrome", foundationYear: "1992", initials: "R92", patternKey: "team.shield.pattern.retro", primaryColorKey: "team.shield.color.crimson", primarySymbolKey: "team.shield.symbol.nested_badge", secondaryColorKey: "team.shield.color.ivory", shapeKey: "team.shield.shape.round" }) },
  { label: "Retro campeón", family: "Retro", density: "CARGADO", config: sampleConfig({ borderKey: "team.shield.border.silver", bottomOrnamentKey: "team.shield.ornament.banner", foundationYear: "1978", initials: "LEY", patternKey: "team.shield.pattern.retro", primaryColorKey: "team.shield.color.emerald", primarySymbolKey: "team.shield.symbol.ball_iq", secondaryColorKey: "team.shield.color.ivory", shapeKey: "team.shield.shape.swiss", sideOrnamentKey: "team.shield.ornament.laurels", topOrnamentKey: "team.shield.ornament.three_stars" }) },
];

const materialSamples: ShieldSample[] = [
  ["Acero", "steel"], ["Cobre", "copper"], ["Plata", "silver"], ["Oro", "gold"], ["Navy", "navy"],
  ["Carbono", "carbon"], ["Cromo", "chrome"], ["Negro mate", "black_matte"], ["Perla", "pearl"],
].map(([label, key]) => ({
  label,
  config: sampleConfig({
    borderKey: `team.shield.border.${key}`,
    initials: label.slice(0, 2).toUpperCase(),
    patternKey: null,
    primarySymbolKey: "team.shield.symbol.star_iq",
    shapeKey: "team.shield.shape.classic_iq",
  }),
}));

const symbolSamples: ShieldSample[] = [
  ["Balón IQ", "ball_iq"], ["Monograma", "monogram"], ["Estrella IQ", "star_iq"], ["Rayo", "bolt"],
  ["Torre", "tower"], ["Torre Elite", "tower_elite"], ["Estrella Future", "iq_star"], ["Corona IQ", "crown_iq"],
  ["Escudo interior", "nested_badge"], ["Órbita IQ", "orbit_ball"],
].map(([label, key]) => ({
  label,
  config: sampleConfig({
    borderKey: "team.shield.border.navy",
    initials: key === "monogram" ? "IQ" : "SYM",
    patternKey: "team.shield.pattern.grid_iq",
    primarySymbolKey: `team.shield.symbol.${key}`,
    shapeKey: "team.shield.shape.hex_iq",
  }),
}));

const effectSamples: ShieldSample[] = [
  ["Sin efecto", null], ["Glint", "glint"], ["Scan", "scan"], ["Edge Glow", "edge_glow"], ["Holo", "holo"],
].map(([label, key]) => ({
  label: label as string,
  config: sampleConfig({
    borderKey: key === "glint" ? "team.shield.border.gold" : "team.shield.border.navy",
    effectKey: key ? `team.shield.effect.${key}` : null,
    initials: "FX",
    patternKey: "team.shield.pattern.grid_iq",
    primarySymbolKey: "team.shield.symbol.iq_star",
    shapeKey: "team.shield.shape.hex_iq",
  }),
}));

const ornamentSamples: ShieldSample[] = [
  ["Corona", "topOrnamentKey", "crown"], ["Tres estrellas", "topOrnamentKey", "three_stars"],
  ["Laureles", "sideOrnamentKey", "laurels"], ["Alas", "sideOrnamentKey", "wings"],
  ["Rayos laterales", "sideOrnamentKey", "side_bolts"], ["Banner", "bottomOrnamentKey", "banner"],
  ["Placa", "bottomOrnamentKey", "plate"],
].map(([label, field, key]) => ({
  label,
  config: sampleConfig({
    borderKey: "team.shield.border.gold",
    initials: "ORN",
    patternKey: null,
    primarySymbolKey: "team.shield.symbol.star_iq",
    [field]: `team.shield.ornament.${key}`,
  }),
}));

function ContactSheet({ id, samples, title, eyebrow }: { id: string; samples: ShieldSample[]; title: string; eyebrow: string }) {
  return (
    <section className={styles.contactBand} id={id}>
      <header><span>{eyebrow}</span><strong>{title}</strong></header>
      <div className={styles.contactGrid}>
        {samples.map((sample) => (
          <article data-density={sample.density ?? "LIMPIO"} key={`${sample.family ?? "sample"}-${sample.label}`}>
            <TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={sample.config} size={82} />
            <div><span>{sample.family ?? eyebrow}</span><strong>{sample.label}</strong>{sample.density ? <small>{sample.density}</small> : null}</div>
          </article>
        ))}
      </div>
    </section>
  );
}

function optionsFor(slot: TeamShieldCosmeticSlot) {
  const direct = TEAM_SHIELD_RENDER_CATALOG.filter((item) => item.slot === slot);
  if (slot === "secondary_symbol") {
    return [...TEAM_SHIELD_BASE_CATALOG.filter((item) => item.slot === "primary_symbol"), ...direct];
  }
  return direct;
}

function selectedKeys(config: TeamShieldConfig, slot: TeamShieldCosmeticSlot) {
  const map: Record<TeamShieldCosmeticSlot, string | null> = {
    background: config.backgroundKey,
    border: config.borderKey,
    bottom_ornament: config.bottomOrnamentKey,
    effect: config.effectKey,
    pattern: config.patternKey,
    primary_symbol: config.primarySymbolKey,
    secondary_symbol: config.secondarySymbolKey,
    shape: config.shapeKey,
    side_ornament: config.sideOrnamentKey,
    top_ornament: config.topOrnamentKey,
  };
  return map[slot] ? [map[slot] as string] : [];
}

function applySelection(config: TeamShieldConfig, slot: TeamShieldCosmeticSlot, key: string | null) {
  if (slot === "shape" && key) return { ...config, shapeKey: key };
  if (slot === "background" && key) return { ...config, backgroundKey: key };
  if (slot === "pattern") return { ...config, patternKey: key };
  if (slot === "primary_symbol" && key) return { ...config, primarySymbolKey: key };
  if (slot === "secondary_symbol") return { ...config, secondarySymbolKey: key };
  if (slot === "border" && key) return { ...config, borderKey: key };
  if (slot === "top_ornament") return { ...config, topOrnamentKey: key };
  if (slot === "side_ornament") return { ...config, sideOrnamentKey: key };
  if (slot === "bottom_ornament") return { ...config, bottomOrnamentKey: key };
  if (slot === "effect") return { ...config, effectKey: key };
  return config;
}

function option(item: TeamShieldCatalogEntry) {
  return {
    key: item.key,
    material: item.material,
    meta: item.availability === "base" ? "BASE" : item.prototype ? "LAB" : item.decision,
    name: item.name,
  };
}

export default function TeamShieldCosmeticsLab() {
  const [activeCategory, setActiveCategory] = useState<TeamShieldCosmeticSlot>("shape");
  const [config, setConfig] = useState<TeamShieldConfig>(presets[0].config);
  const [savedConfig, setSavedConfig] = useState<TeamShieldConfig>(presets[0].config);
  const [previewMotion, setPreviewMotion] = useState<"auto" | "reduced">("auto");
  const options = useMemo(() => optionsFor(activeCategory).map(option), [activeCategory]);
  const dirty = !teamShieldDesignEquals(config, savedConfig);
  const optional = activeCategory === "pattern" || activeCategory === "secondary_symbol"
    || activeCategory === "top_ornament" || activeCategory === "side_ornament"
    || activeCategory === "bottom_ornament" || activeCategory === "effect";

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div><span>LABORATORIO · NOINDEX</span><h1>Team Shield Cosmetics</h1></div>
        <strong>{TEAM_SHIELD_COSMETIC_V1_CANDIDATES.length} candidatas V1 · {TEAM_SHIELD_COSMETIC_PROTOTYPES.length} propuestas</strong>
      </header>

      <section className={styles.presetRail} aria-label="Colecciones">
        {presets.map((preset) => <button key={preset.label} type="button" onClick={() => setConfig(preset.config)}>{preset.label}</button>)}
      </section>

      <CosmeticEditorShell
        className={styles.editorShell}
        preview={<div className={styles.previewStage}><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={config} motion={previewMotion} /><div className={styles.motionControl} aria-label="Movimiento del efecto"><button className={previewMotion === "auto" ? styles.activeMotion : ""} type="button" onClick={() => setPreviewMotion("auto")}>Activo</button><button className={previewMotion === "reduced" ? styles.activeMotion : ""} type="button" onClick={() => setPreviewMotion("reduced")}>Reducido</button></div><small>Preview local · servidor sin modificar</small></div>}
        actions={<div className={styles.actionRow}><UnsavedChanges dirty={dirty} synchronizedLabel="Escudo sincronizado" /><EditorActions primaryDisabled={!dirty} primaryLabel="Simular guardado" onPrimary={() => setSavedConfig(config)} onReset={() => setConfig(savedConfig)} /></div>}
      >
        <CosmeticCategoryNav active={activeCategory} ariaLabel="Capas del escudo" items={tabs} onChange={setActiveCategory} />
        <div className={styles.identityControls}>
          <label>Iniciales<input maxLength={4} value={config.initials} onChange={(event) => setConfig((current) => ({ ...current, initials: event.target.value.toUpperCase().replace(/\s/g, "").slice(0, 4) }))} /></label>
          <label>Año<input inputMode="numeric" maxLength={4} placeholder="Opcional" value={config.foundationYear} onChange={(event) => setConfig((current) => ({ ...current, foundationYear: event.target.value.replace(/[^0-9]/g, "").slice(0, 4) }))} /></label>
          <div><span>Principal</span><div className={styles.swatches}>{colors.map((item) => <button aria-label={`Principal ${item.name}`} className={config.primaryColorKey === item.key ? styles.activeSwatch : ""} key={`p-${item.key}`} style={{ background: String(item.render.hex) }} type="button" onClick={() => setConfig((current) => ({ ...current, primaryColorKey: item.key }))} />)}</div></div>
          <div><span>Secundario</span><div className={styles.swatches}>{colors.map((item) => <button aria-label={`Secundario ${item.name}`} className={config.secondaryColorKey === item.key ? styles.activeSwatch : ""} key={`s-${item.key}`} style={{ background: String(item.render.hex) }} type="button" onClick={() => setConfig((current) => ({ ...current, secondaryColorKey: item.key }))} />)}</div></div>
        </div>
        {activeCategory === "primary_symbol" ? (
          <div className={styles.symbolControls}>
            <label>Escala<input type="range" min="0.8" max="1.2" step="0.05" value={config.primarySymbolScale} onChange={(event) => setConfig((current) => ({ ...current, primarySymbolScale: Number(event.target.value) }))} /></label>
            <label>Giro<input type="range" min="-12" max="12" step="1" value={config.primarySymbolRotation} onChange={(event) => setConfig((current) => ({ ...current, primarySymbolRotation: Number(event.target.value) }))} /></label>
          </div>
        ) : null}
        <CosmeticOptionSelector items={options} noneLabel={optional ? "Ninguno" : undefined} selectedKeys={selectedKeys(config, activeCategory)} onChange={(key) => setConfig((current) => applySelection(current, activeCategory, key))} />
      </CosmeticEditorShell>

      <section className={styles.baselineBand}>
        <header><span>Base gratuita nueva</span><strong>Bonita antes de cualquier premio</strong></header>
        {presets.slice(0, 3).map((preset) => <article key={preset.label}><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={preset.config} /><div><strong>{preset.label}</strong><small>TeamShieldConfig V1</small></div></article>)}
      </section>

      <ContactSheet id="contact-sheet-families" samples={familySamples} eyebrow="Contact sheet general" title="5 familias · 15 combinaciones" />
      <ContactSheet id="contact-sheet-materials" samples={materialSamples} eyebrow="Materiales" title="9 acabados al mismo tamaño" />
      <ContactSheet id="contact-sheet-symbols" samples={symbolSamples} eyebrow="Símbolos SVG" title="Barrio, fútbol, heráldica y Future IQ" />
      <ContactSheet id="contact-sheet-effects" samples={effectSamples} eyebrow="Efectos" title="Referencia sin efecto + 4 tratamientos" />
      <ContactSheet id="contact-sheet-ornaments" samples={ornamentSamples} eyebrow="Ornamentos" title="Superior, laterales e inferior" />

      <section className={styles.sizeBand} id="contact-sheet-lod">
        <header><span>LOD real</span><strong>24 / 32 / 48 / 64 px</strong></header>
        {[24, 32, 48, 64].map((size) => <article key={size}><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={config} size={size as 24 | 32 | 48 | 64} /><small>{size}px</small></article>)}
      </section>

      <section className={styles.motionBand} id="contact-sheet-reduced-motion">
        <header><span>Reduced motion</span><strong>Estado estático reconocible</strong></header>
        <div>
          {effectSamples.slice(1).map((sample) => <article key={`reduced-${sample.label}`}><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={sample.config} motion="reduced" size={82} /><strong>{sample.label}</strong><small>Sin animación</small></article>)}
        </div>
      </section>

      <section className={styles.catalogBand} id="catalog-decisions">
        <header><span>Propuestas V0.1</span><strong>{TEAM_SHIELD_COSMETIC_PROTOTYPES.length}</strong></header>
        <div className={styles.catalogGrid}>
          {TEAM_SHIELD_COSMETIC_PROTOTYPES.map((item) => (
            <article data-decision={item.decision} key={item.key}>
              <span>{item.collection} · {item.slot ? item.slot.replaceAll("_", " ") : "palette"}</span>
              <strong>{item.name}</strong>
              <p>{item.description}</p>
              <small>{item.decision}{item.prototype ? " · LAB ONLY" : ""}</small>
            </article>
          ))}
        </div>
      </section>
    </main>
  );
}
