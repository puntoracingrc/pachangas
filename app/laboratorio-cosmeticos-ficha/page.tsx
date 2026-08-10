"use client";

import { useMemo, useState } from "react";
import {
  CosmeticCategoryTabs,
  CosmeticEditorShell,
  EditorActions,
  OwnedCosmeticSelector,
} from "../_components/cosmetics-editor";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import {
  PLAYER_COSMETIC_CATALOG,
  PLAYER_COSMETIC_PROTOTYPES,
  PLAYER_COSMETIC_RARITY_LABELS,
  PLAYER_COSMETIC_SLOT_LABELS,
} from "../player-cosmetics-catalog";
import {
  EMPTY_PLAYER_COSMETIC_LOADOUT,
  cosmeticKeyForSlot,
  withCosmeticKey,
  type PlayerCosmeticItem,
  type PlayerCosmeticLoadout,
  type PlayerCosmeticSlot,
  type PlayerFeaturedBadge,
} from "../player-cosmetics-contract";
import styles from "./page.module.css";

type EditorCategory = PlayerCosmeticSlot | "badge";

const FACETS = [
  { key: "ritmo", value: 78, label: "RIT" },
  { key: "tiro", value: 72, label: "TIR" },
  { key: "pase", value: 81, label: "PAS" },
  { key: "regate", value: 79, label: "REG" },
  { key: "defensa", value: 64, label: "DEF" },
  { key: "fisico", value: 76, label: "FÍS" },
];

const LAB_BADGES: PlayerFeaturedBadge[] = [
  { achievementKey: "player.hat_trick", grantId: "lab-hat-trick", rarity: "rare", title: "Hat-trick" },
  { achievementKey: "player.first_win", grantId: "lab-first-win", rarity: "common", title: "Primera conquista" },
  { achievementKey: "player.poker", grantId: "lab-poker", rarity: "epic", title: "Póker" },
];

const ORIGINAL = { ...EMPTY_PLAYER_COSMETIC_LOADOUT };

const PRESETS: Array<{ id: string; label: string; loadout: PlayerCosmeticLoadout }> = [
  { id: "original", label: "Original", loadout: ORIGINAL },
  { id: "barrio", label: "Barrio", loadout: { ...ORIGINAL, accentKey: "player.accent.copper", frameKey: "player.frame.barrio.steel", titleKey: "player.title.old_school", featuredBadgeGrantId: "lab-hat-trick" } },
  { id: "noche", label: "Noche", loadout: { ...ORIGINAL, backgroundKey: "player.background.asphalt_night", effectKey: "player.effect.spotlights", titleKey: "player.title.team_engine", featuredBadgeGrantId: "lab-first-win" } },
  { id: "retro", label: "Retro", loadout: { ...ORIGINAL, backgroundKey: "prototype.background.paper_league", frameKey: "player.frame.retro.chrome", featuredBadgeGrantId: "lab-hat-trick" } },
  { id: "future", label: "Future IQ", loadout: { ...ORIGINAL, accentKey: "player.accent.navy", backgroundKey: "player.background.grid_iq", effectKey: "player.effect.iq_scan", frameKey: "player.frame.future.navy", featuredBadgeGrantId: "lab-poker" } },
];

const LAB_ITEMS: PlayerCosmeticItem[] = PLAYER_COSMETIC_PROTOTYPES.map((entry, index) => ({
  acquiredAt: "2026-08-10T00:00:00.000Z",
  collection: entry.collection,
  description: entry.description,
  key: entry.key,
  layerOrder: index,
  material: entry.material,
  name: entry.name,
  rarity: entry.rarity,
  render: entry.render,
  seenAt: "2026-08-10T00:00:00.000Z",
  serverSequence: index + 1,
  slot: entry.slot,
  sourceBoxId: null,
}));

function sampleLoadout(slot: PlayerCosmeticSlot, key: string) {
  return withCosmeticKey({ ...ORIGINAL }, slot, key);
}

function PreviewCard({ compact = false, loadout, name }: { compact?: boolean; loadout: PlayerCosmeticLoadout; name: string }) {
  const featuredAchievement = LAB_BADGES.find((badge) => badge.grantId === loadout.featuredBadgeGrantId) ?? null;
  return (
    <div className={`${styles.cardStage} ${compact ? styles.compactCardStage : ""}`}>
      <PlayerCosmeticCard
        ariaLabel={`Ficha de preview de ${name}`}
        className={`fifa-card-gold readonly-card ${styles.cosmeticCard}`}
        cosmetics={LAB_ITEMS}
        facets={FACETS}
        featuredAchievement={featuredAchievement}
        loadout={loadout}
        meta="14 Goles · 28 PJ · 29 años"
        name={name}
        photoAlt={`Retrato de preview de ${name}`}
        photoSrc="/lab/player-card-preview.jpg"
        position="MC"
        score={78}
      />
    </div>
  );
}

export default function PlayerCardCosmeticsLabPage() {
  const [activeCategory, setActiveCategory] = useState<EditorCategory>("frame");
  const [compareOriginal, setCompareOriginal] = useState(false);
  const [loadout, setLoadout] = useState<PlayerCosmeticLoadout>(PRESETS[1].loadout);
  const [playerName, setPlayerName] = useState("Marc");
  const activePreset = useMemo(
    () => PRESETS.find((preset) => JSON.stringify(preset.loadout) === JSON.stringify(loadout))?.id ?? "custom",
    [loadout],
  );
  const items = activeCategory === "badge" ? [] : LAB_ITEMS.filter((item) => item.slot === activeCategory);
  const counts = { accent: 0, background: 0, badge: 0, effect: 0, frame: 0, title: 0 };

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div><span className={styles.labLabel}>Laboratorio visual V0.2</span><h1>Cosméticos de ficha</h1></div>
        <strong>{PLAYER_COSMETIC_PROTOTYPES.length} prototipos · {PLAYER_COSMETIC_CATALOG.length} seleccionados</strong>
      </header>

      <nav className={styles.presetBar} aria-label="Colecciones de preview">
        {PRESETS.map((preset) => (
          <button className={activePreset === preset.id ? styles.activePreset : ""} key={preset.id} type="button" onClick={() => setLoadout(preset.loadout)}>
            {preset.label}
          </button>
        ))}
      </nav>

      <div className={styles.labEditor}>
        <CosmeticEditorShell
          actions={(
            <EditorActions
              onPrimary={() => setCompareOriginal((current) => !current)}
              onReset={() => setLoadout({ ...ORIGINAL })}
              primaryLabel={compareOriginal ? "Ocultar original" : "Comparar original"}
            />
          )}
          preview={(
            <div className={`${styles.cardComparison} ${compareOriginal ? styles.comparing : ""}`}>
              {compareOriginal ? <figure><PreviewCard loadout={ORIGINAL} name={playerName} /><figcaption>Original</figcaption></figure> : null}
              <figure><PreviewCard loadout={loadout} name={playerName} /><figcaption>{activePreset === "custom" ? "Personalizada" : activePreset}</figcaption></figure>
            </div>
          )}
        >
          <CosmeticCategoryTabs active={activeCategory} counts={counts} onChange={setActiveCategory} />
          <label className={styles.selectControl}>
            <span>Nombre de prueba</span>
            <select value={playerName} onChange={(event) => setPlayerName(event.target.value)}>
              <option>Marc</option><option>Alejandro Martínez</option>
            </select>
          </label>
          {activeCategory === "badge" ? (
            <div className={styles.badgeOptions}>
              <button type="button" onClick={() => setLoadout((current) => ({ ...current, featuredBadgeGrantId: null }))}>Sin logro</button>
              {LAB_BADGES.map((badge) => <button key={badge.grantId} type="button" onClick={() => setLoadout((current) => ({ ...current, featuredBadgeGrantId: badge.grantId }))}>{badge.title}</button>)}
            </div>
          ) : (
            <OwnedCosmeticSelector
              items={items}
              noneLabel={activeCategory === "effect" || activeCategory === "title" ? "Ninguno" : "Original"}
              onChange={(key) => setLoadout((current) => withCosmeticKey(current, activeCategory, key))}
              selectedKey={cosmeticKeyForSlot(loadout, activeCategory)}
            />
          )}
        </CosmeticEditorShell>
      </div>

      <section className={styles.gallery} aria-labelledby="gallery-title">
        <div className={styles.sectionHeading}>
          <span>{PLAYER_COSMETIC_PROTOTYPES.length} muestras</span>
          <h2 id="gallery-title">Exploración por pieza</h2>
        </div>
        <div className={styles.galleryGrid}>
          {PLAYER_COSMETIC_PROTOTYPES.map((sample) => (
            <article className={styles.sampleCard} data-selected={!sample.prototype} key={sample.key}>
              <PreviewCard compact loadout={sampleLoadout(sample.slot, sample.key)} name="Marc" />
              <div className={styles.sampleCopy}>
                <span>{sample.collection}</span>
                <h3>{sample.name}</h3>
                <div>
                  <small>{PLAYER_COSMETIC_SLOT_LABELS[sample.slot]}</small>
                  <small>{PLAYER_COSMETIC_RARITY_LABELS[sample.rarity]}</small>
                  <small>{sample.prototype ? "Prototipo" : "Catálogo V1"}</small>
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.futureFlow} aria-label="Flujo real de cosméticos">
        <span>Arquitectura conectada</span>
        <div><b>achievement</b><i>→</i><b>box</b><i>→</i><b>inventory</b><i>→</i><b>loadout</b><i>→</i><b>public card</b></div>
        <small>{PLAYER_COSMETIC_CATALOG.length} piezas reales; el resto permanece solo en laboratorio.</small>
      </section>
    </main>
  );
}
