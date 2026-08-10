"use client";

import { useMemo, useState } from "react";
import { PlayerCardView } from "../_components/player-card-view";
import styles from "./page.module.css";

type FrameId = "none" | "barrio-acero" | "retro-cromo" | "future-iq";
type BackgroundId = "none" | "asfalto-nocturno" | "papel-liga" | "grid-iq";
type EffectId = "none" | "focos" | "iq-scan";
type TitleId = "none" | "de-toda-la-vida" | "motor-del-equipo";
type BadgeId = "none" | "hat-trick" | "primera-conquista" | "poker";
type CosmeticSlot = "card_frame" | "card_background" | "card_effect" | "player_title";

type Selection = {
  background: BackgroundId;
  badge: BadgeId;
  effect: EffectId;
  frame: FrameId;
  title: TitleId;
};

type CosmeticSample = {
  collection: "Fútbol de Barrio" | "Noche de Partido" | "Retro" | "Future IQ";
  id: Exclude<FrameId | BackgroundId | EffectId | TitleId, "none">;
  name: string;
  rarity: "Común" | "Poco común" | "Raro";
  release: "collectible" | "merit_locked" | "prestige";
  slot: CosmeticSlot;
};

const ORIGINAL_SELECTION: Selection = {
  background: "none",
  badge: "none",
  effect: "none",
  frame: "none",
  title: "none",
};

const COSMETICS: CosmeticSample[] = [
  { id: "barrio-acero", name: "Barrio Acero", collection: "Fútbol de Barrio", slot: "card_frame", rarity: "Común", release: "collectible" },
  { id: "retro-cromo", name: "Retro Cromo", collection: "Retro", slot: "card_frame", rarity: "Poco común", release: "collectible" },
  { id: "future-iq", name: "Future IQ", collection: "Future IQ", slot: "card_frame", rarity: "Raro", release: "prestige" },
  { id: "asfalto-nocturno", name: "Asfalto Nocturno", collection: "Noche de Partido", slot: "card_background", rarity: "Común", release: "collectible" },
  { id: "papel-liga", name: "Papel de Liga", collection: "Retro", slot: "card_background", rarity: "Común", release: "collectible" },
  { id: "grid-iq", name: "Grid IQ", collection: "Future IQ", slot: "card_background", rarity: "Poco común", release: "collectible" },
  { id: "focos", name: "Focos", collection: "Noche de Partido", slot: "card_effect", rarity: "Poco común", release: "collectible" },
  { id: "iq-scan", name: "IQ Scan", collection: "Future IQ", slot: "card_effect", rarity: "Raro", release: "prestige" },
  { id: "de-toda-la-vida", name: "De toda la vida", collection: "Fútbol de Barrio", slot: "player_title", rarity: "Común", release: "collectible" },
  { id: "motor-del-equipo", name: "Motor del equipo", collection: "Noche de Partido", slot: "player_title", rarity: "Raro", release: "merit_locked" },
];

const FRAME_OPTIONS: Array<{ id: FrameId; label: string }> = [
  { id: "none", label: "Original" },
  { id: "barrio-acero", label: "Barrio Acero" },
  { id: "retro-cromo", label: "Retro Cromo" },
  { id: "future-iq", label: "Future IQ" },
];

const BACKGROUND_OPTIONS: Array<{ id: BackgroundId; label: string }> = [
  { id: "none", label: "Original" },
  { id: "asfalto-nocturno", label: "Asfalto Nocturno" },
  { id: "papel-liga", label: "Papel de Liga" },
  { id: "grid-iq", label: "Grid IQ" },
];

const EFFECT_OPTIONS: Array<{ id: EffectId; label: string }> = [
  { id: "none", label: "Sin efecto" },
  { id: "focos", label: "Focos" },
  { id: "iq-scan", label: "IQ Scan" },
];

const TITLE_OPTIONS: Array<{ id: TitleId; label: string }> = [
  { id: "none", label: "Sin título" },
  { id: "de-toda-la-vida", label: "De toda la vida" },
  { id: "motor-del-equipo", label: "Motor del equipo" },
];

const BADGE_OPTIONS: Array<{ id: BadgeId; label: string }> = [
  { id: "none", label: "Sin logro" },
  { id: "hat-trick", label: "Hat-trick" },
  { id: "primera-conquista", label: "Primera conquista" },
  { id: "poker", label: "Póker" },
];

const PRESETS: Array<{ id: string; label: string; selection: Selection }> = [
  { id: "original", label: "Original", selection: ORIGINAL_SELECTION },
  { id: "barrio", label: "Barrio", selection: { frame: "barrio-acero", background: "none", effect: "none", title: "de-toda-la-vida", badge: "hat-trick" } },
  { id: "noche", label: "Noche", selection: { frame: "none", background: "asfalto-nocturno", effect: "focos", title: "motor-del-equipo", badge: "primera-conquista" } },
  { id: "retro", label: "Retro", selection: { frame: "retro-cromo", background: "papel-liga", effect: "none", title: "none", badge: "hat-trick" } },
  { id: "future", label: "Future IQ", selection: { frame: "future-iq", background: "grid-iq", effect: "iq-scan", title: "none", badge: "poker" } },
];

const FACETS = [
  { key: "ritmo", value: 78, label: "RIT" },
  { key: "tiro", value: 72, label: "TIR" },
  { key: "pase", value: 81, label: "PAS" },
  { key: "regate", value: 79, label: "REG" },
  { key: "defensa", value: 64, label: "DEF" },
  { key: "fisico", value: 76, label: "FÍS" },
];

const frameClasses: Record<FrameId, string> = {
  none: "",
  "barrio-acero": styles.frameBarrio,
  "retro-cromo": styles.frameRetro,
  "future-iq": styles.frameFuture,
};

const backgroundClasses: Record<BackgroundId, string> = {
  none: "",
  "asfalto-nocturno": styles.backgroundAsphalt,
  "papel-liga": styles.backgroundPaper,
  "grid-iq": styles.backgroundGrid,
};

const effectClasses: Record<EffectId, string> = {
  none: "",
  focos: styles.effectLights,
  "iq-scan": styles.effectScan,
};

const titleLabels: Record<TitleId, string | undefined> = {
  none: undefined,
  "de-toda-la-vida": "De toda la vida",
  "motor-del-equipo": "Motor del equipo",
};

const badgeLabels: Record<BadgeId, string | undefined> = {
  none: undefined,
  "hat-trick": "Hat-trick",
  "primera-conquista": "Primera conquista",
  poker: "Póker",
};

function selectionForSample(sample: CosmeticSample): Selection {
  const selection = { ...ORIGINAL_SELECTION };
  if (sample.slot === "card_frame") selection.frame = sample.id as FrameId;
  if (sample.slot === "card_background") selection.background = sample.id as BackgroundId;
  if (sample.slot === "card_effect") selection.effect = sample.id as EffectId;
  if (sample.slot === "player_title") selection.title = sample.id as TitleId;
  return selection;
}

function CosmeticCard({ compact = false, name, selection }: { compact?: boolean; name: string; selection: Selection }) {
  const title = titleLabels[selection.title];
  const badge = badgeLabels[selection.badge];
  const stageClassName = [
    styles.cardStage,
    compact ? styles.compactCardStage : "",
    frameClasses[selection.frame],
    backgroundClasses[selection.background],
    effectClasses[selection.effect],
  ].filter(Boolean).join(" ");

  return (
    <div className={stageClassName} data-effect={selection.effect}>
      <PlayerCardView
        ariaLabel={`Ficha de preview de ${name}`}
        className={`fifa-card-gold readonly-card ${styles.cosmeticCard}`}
        facets={FACETS}
        featuredBadge={badge ? (
          <span className={styles.featuredBadge} title="Logro real usado solo como preview">
            <span aria-hidden="true">★</span>
            {badge}
          </span>
        ) : undefined}
        meta="14 Goles · 28 PJ · 29 años"
        name={name}
        photoAlt={`Retrato de preview de ${name}`}
        photoSrc="/lab/player-card-preview.jpg"
        position="MC"
        score={78}
        title={title ? <span className={styles.playerTitle}>{title}</span> : undefined}
      />
      <span className={styles.effectLayer} aria-hidden="true" />
    </div>
  );
}

function SelectControl<T extends string>({ label, onChange, options, value }: { label: string; onChange: (value: T) => void; options: Array<{ id: T; label: string }>; value: T }) {
  return (
    <label className={styles.selectControl}>
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value as T)}>
        {options.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
      </select>
    </label>
  );
}

export default function PlayerCardCosmeticsLabPage() {
  const [selection, setSelection] = useState<Selection>(PRESETS[1].selection);
  const [compareOriginal, setCompareOriginal] = useState(false);
  const [playerName, setPlayerName] = useState("Marc");
  const activePreset = useMemo(() => PRESETS.find((preset) => JSON.stringify(preset.selection) === JSON.stringify(selection))?.id ?? "custom", [selection]);

  function updateSelection<Key extends keyof Selection>(key: Key, value: Selection[Key]) {
    setSelection((current) => ({ ...current, [key]: value }));
  }

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div>
          <span className={styles.labLabel}>Laboratorio visual</span>
          <h1>Cosméticos de ficha</h1>
        </div>
        <strong>No es catálogo definitivo</strong>
      </header>

      <nav className={styles.presetBar} aria-label="Colecciones de preview">
        {PRESETS.map((preset) => (
          <button key={preset.id} className={activePreset === preset.id ? styles.activePreset : ""} type="button" onClick={() => setSelection(preset.selection)}>
            {preset.label}
          </button>
        ))}
      </nav>

      <section className={styles.workspace} aria-label="Configurador de cosméticos">
        <aside className={styles.controls}>
          <div className={styles.panelHeading}>
            <span>Composición</span>
            <b>{activePreset === "custom" ? "Personalizada" : PRESETS.find((preset) => preset.id === activePreset)?.label}</b>
          </div>
          <SelectControl label="Marco" value={selection.frame} options={FRAME_OPTIONS} onChange={(value) => updateSelection("frame", value)} />
          <SelectControl label="Fondo" value={selection.background} options={BACKGROUND_OPTIONS} onChange={(value) => updateSelection("background", value)} />
          <SelectControl label="Efecto" value={selection.effect} options={EFFECT_OPTIONS} onChange={(value) => updateSelection("effect", value)} />
          <SelectControl label="Título" value={selection.title} options={TITLE_OPTIONS} onChange={(value) => updateSelection("title", value)} />
          <SelectControl label="Badge" value={selection.badge} options={BADGE_OPTIONS} onChange={(value) => updateSelection("badge", value)} />
          <SelectControl label="Nombre de prueba" value={playerName} options={[{ id: "Marc", label: "Marc" }, { id: "Alejandro Martínez", label: "Alejandro Martínez" }]} onChange={setPlayerName} />
          <div className={styles.controlActions}>
            <button type="button" onClick={() => setSelection(ORIGINAL_SELECTION)}>Restablecer</button>
            <label className={styles.compareToggle}>
              <input type="checkbox" checked={compareOriginal} onChange={(event) => setCompareOriginal(event.target.checked)} />
              <span>Comparar con original</span>
            </label>
          </div>
        </aside>

        <div className={styles.previewPanel}>
          <div className={styles.panelHeading}>
            <span>Carta en tiempo real</span>
            <b>Preview local</b>
          </div>
          <div className={`${styles.cardComparison} ${compareOriginal ? styles.comparing : ""}`}>
            {compareOriginal ? (
              <figure>
                <CosmeticCard name={playerName} selection={ORIGINAL_SELECTION} />
                <figcaption>Original</figcaption>
              </figure>
            ) : null}
            <figure>
              <CosmeticCard name={playerName} selection={selection} />
              <figcaption>{activePreset === "original" ? "Original" : "Cosmética"}</figcaption>
            </figure>
          </div>
        </div>
      </section>

      <section className={styles.gallery} aria-labelledby="gallery-title">
        <div className={styles.sectionHeading}>
          <span>10 muestras</span>
          <h2 id="gallery-title">Galería por pieza</h2>
        </div>
        <div className={styles.galleryGrid}>
          {COSMETICS.map((sample) => (
            <article className={styles.sampleCard} key={sample.id}>
              <CosmeticCard compact name="Marc" selection={selectionForSample(sample)} />
              <div className={styles.sampleCopy}>
                <span>{sample.collection}</span>
                <h3>{sample.name}</h3>
                <div>
                  <small>{sample.slot}</small>
                  <small>{sample.rarity}</small>
                  <small>{sample.release}</small>
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.futureFlow} aria-label="Conexión futura no implementada">
        <span>Siguiente fase</span>
        <div>
          <b>achievement</b><i>→</i><b>box</b><i>→</i><b>cosmetic reward</b><i>→</i><b>inventory</b><i>→</i><b>loadout</b><i>→</i><b>player card</b>
        </div>
        <small>Contrato conceptual · sin propiedad ni equipamiento</small>
      </section>
    </main>
  );
}
