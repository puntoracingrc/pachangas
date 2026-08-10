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
    config: {
      ...TEAM_SHIELD_DEFAULT_CONFIG,
      borderKey: "team.shield.border.gold",
      effectKey: "team.shield.effect.glint",
      foundationYear: "2026",
      initials: "NOC",
      primaryColorKey: "team.shield.color.midnight",
      primarySymbolKey: "team.shield.symbol.bolt",
      secondaryColorKey: "team.shield.color.amber",
      shapeKey: "team.shield.shape.tall",
      topOrnamentKey: "team.shield.ornament.crown",
    },
  },
];

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
        preview={<div className={styles.previewStage}><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={config} /><small>Preview local · servidor sin modificar</small></div>}
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

      <section className={styles.sizeBand}>
        <header><span>LOD real</span><strong>24 / 32 / 48 / 64 px</strong></header>
        {[24, 32, 48, 64].map((size) => <article key={size}><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={config} size={size as 24 | 32 | 48 | 64} /><small>{size}px</small></article>)}
      </section>

      <section className={styles.catalogBand}>
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
