"use client";

import { useEffect, useMemo, useState, type CSSProperties } from "react";
import dynamic from "next/dynamic";
import Image from "next/image";
import { TeamShieldView } from "../_components/team-shield-view";
import { TEAM_SHIELD_RENDER_CATALOG } from "../team-shield-cosmetics-catalog";
import { TEAM_SHIELD_DEFAULT_CONFIG } from "../team-shield-contract";
import type { PremiumCrownMaterial, PremiumFrameMaterial } from "./_components/premium-shield-3d";
import { usePremiumMotion, type PremiumTilt } from "./_components/use-premium-motion";
import styles from "./page.module.css";

type Pipeline = "A" | "B" | "C";
type MotionMode = "active" | "off" | "reduced";
type ShieldStyle = CSSProperties;

const PremiumShield3D = dynamic(
  () => import("./_components/premium-shield-3d").then((module) => module.PremiumShield3D),
  {
    loading: () => <div className="premium-three-stage"><span role="status">Cargando modelo 3D</span></div>,
    ssr: false,
  },
);

const PIPELINES: Array<{ key: Pipeline; label: string; short: string }> = [
  { key: "A", label: "Render", short: "Imagen" },
  { key: "B", label: "Sprite", short: "8 vistas" },
  { key: "C", label: "Tiempo real", short: "GLB" },
];

const MATERIALS: Array<{ color: string; key: PremiumFrameMaterial; label: string }> = [
  { color: "#b84a16", key: "copper", label: "Cobre" },
  { color: "#a8bbc7", key: "silver", label: "Plata" },
  { color: "#d98e18", key: "gold", label: "Oro" },
  { color: "#d8edf4", key: "chrome", label: "Cromo" },
  { color: "#151a1f", key: "carbon", label: "Carbono" },
];

const LOD_CONFIG = {
  ...TEAM_SHIELD_DEFAULT_CONFIG,
  borderKey: "team.shield.border.gold",
  initials: "PIQ",
  topOrnamentKey: "team.shield.ornament.crown",
};

function crownSource(crown: PremiumCrownMaterial) {
  return crown === "none" ? null : `/team-shield-premium-3d/crown-premium-${crown}-overlay.webp`;
}

function LayeredShield({
  crown,
  material,
  pipeline,
  reduced,
  size,
  tilt,
}: {
  crown: PremiumCrownMaterial;
  material: PremiumFrameMaterial;
  pipeline: "A" | "B";
  reduced: boolean;
  size?: number;
  tilt: PremiumTilt;
}) {
  const frame = reduced || pipeline === "A"
    ? 0
    : Math.round(((Math.max(-6, Math.min(6, tilt.y)) + 6) / 12) * 7);
  const transform = reduced
    ? "rotateX(0deg) rotateY(0deg)"
    : `rotateX(${tilt.x}deg) rotateY(${tilt.y}deg)`;
  const shieldStyle: ShieldStyle = { maxWidth: size ? `${size}px` : undefined, transform };
  return (
    <div
      aria-label={`Escudo premium ${material} con pipeline ${pipeline}`}
      className={styles.layeredShield}
      data-frame-count="8"
      data-pipeline={pipeline}
      data-sprite-frame={frame}
      role="img"
      style={shieldStyle}
    >
      {/* Assets transparentes generados por Blender; no son estado de producto. */}
      <Image alt="" aria-hidden="true" fill sizes={size ? `${size}px` : "(max-width: 760px) 82vw, 530px"} src={`/team-shield-premium-3d/shield-premium-${material}-base.webp`} unoptimized />
      {crownSource(crown) ? <Image alt="" aria-hidden="true" className={styles.crownLayer} fill loading="eager" sizes={size ? `${size}px` : "(max-width: 760px) 82vw, 530px"} src={crownSource(crown) ?? ""} unoptimized /> : null}
      <Image alt="" aria-hidden="true" className={styles.ballFrame} fill sizes={size ? `${Math.ceil(size / 3)}px` : "180px"} src={`/team-shield-premium-3d/ball-premium-frame-${frame}.webp`} unoptimized />
    </div>
  );
}

function PipelineView({
  crown,
  material,
  pipeline,
  reduced,
  tilt,
}: {
  crown: PremiumCrownMaterial;
  material: PremiumFrameMaterial;
  pipeline: Pipeline;
  reduced: boolean;
  tilt: PremiumTilt;
}) {
  if (pipeline === "C") {
    return <PremiumShield3D crown={crown} material={material} reduced={reduced} tilt={tilt} />;
  }
  return <LayeredShield crown={crown} material={material} pipeline={pipeline} reduced={reduced} tilt={tilt} />;
}

export default function TeamShieldPremium3DLabPage() {
  const [crown, setCrown] = useState<PremiumCrownMaterial>("gold");
  const [material, setMaterial] = useState<PremiumFrameMaterial>("gold");
  const [motionMode, setMotionMode] = useState<MotionMode>("active");
  const [pipeline, setPipeline] = useState<Pipeline>("A");
  const [systemReduced, setSystemReduced] = useState(false);
  const motionEnabled = motionMode === "active";
  const reduced = systemReduced || motionMode !== "active";
  const motion = usePremiumMotion({ enabled: motionEnabled, reduced });

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setSystemReduced(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  const sourceLabel = useMemo(() => {
    if (systemReduced) return "Sistema reducido";
    if (motion.source === "sensor") return "Sensor";
    if (motion.source === "pointer") return "Puntero";
    if (motion.source === "simulation") return "Simulación";
    if (motion.source === "reduced") return "Reducido";
    return "Estático";
  }, [motion.source, systemReduced]);

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div>
          <span>Visual Lab V0.1</span>
          <h1>Escudo premium 3D</h1>
        </div>
        <strong>Local · sin persistencia</strong>
      </header>

      <section
        className={styles.hero}
        data-motion-source={motion.source}
        onPointerLeave={motion.resetPointer}
        onPointerMove={motion.handlePointerMove}
      >
        <aside className={styles.controls} aria-label="Controles del laboratorio">
          <fieldset>
            <legend>Pipeline</legend>
            <div className={styles.segmented}>
              {PIPELINES.map((entry) => (
                <button
                  aria-pressed={pipeline === entry.key}
                  className={pipeline === entry.key ? styles.selected : ""}
                  key={entry.key}
                  onClick={() => setPipeline(entry.key)}
                  type="button"
                >
                  <b>{entry.key}</b><small>{entry.short}</small>
                </button>
              ))}
            </div>
          </fieldset>

          <fieldset>
            <legend>Marco</legend>
            <div className={styles.swatches}>
              {MATERIALS.map((entry) => (
                <button
                  aria-label={entry.label}
                  aria-pressed={material === entry.key}
                  className={material === entry.key ? styles.selectedSwatch : ""}
                  key={entry.key}
                  onClick={() => setMaterial(entry.key)}
                  style={{ background: entry.color }}
                  title={entry.label}
                  type="button"
                />
              ))}
            </div>
          </fieldset>

          <fieldset>
            <legend>Corona</legend>
            <div className={styles.textSegments}>
              {(["gold", "chrome", "none"] as const).map((entry) => (
                <button
                  aria-pressed={crown === entry}
                  className={crown === entry ? styles.selected : ""}
                  key={entry}
                  onClick={() => setCrown(entry)}
                  type="button"
                >
                  {entry === "gold" ? "Oro" : entry === "chrome" ? "Cromo" : "Sin"}
                </button>
              ))}
            </div>
          </fieldset>

          <fieldset>
            <legend>Movimiento</legend>
            <div className={styles.textSegments}>
              {(["active", "off", "reduced"] as const).map((entry) => (
                <button
                  aria-pressed={motionMode === entry}
                  className={motionMode === entry ? styles.selected : ""}
                  key={entry}
                  onClick={() => setMotionMode(entry)}
                  type="button"
                >
                  {entry === "active" ? "Activo" : entry === "off" ? "Quieto" : "Reducido"}
                </button>
              ))}
            </div>
          </fieldset>

          <div className={styles.sensorRow}>
            <button disabled={reduced || motion.sensorPermission === "unavailable"} onClick={motion.requestSensor} type="button">
              {motion.sensorPermission === "granted" ? "Sensor activo" : "Activar sensor"}
            </button>
            <span>{sourceLabel}</span>
          </div>

          <div className={styles.tiltControls} aria-label="Simulación de inclinación">
            <label>
              X
              <input
                disabled={reduced}
                max="6"
                min="-6"
                onChange={(event) => motion.simulateTilt({ ...motion.tilt, x: Number(event.target.value) })}
                step="1"
                type="range"
                value={Math.round(motion.tilt.x)}
              />
            </label>
            <label>
              Y
              <input
                disabled={reduced}
                max="6"
                min="-6"
                onChange={(event) => motion.simulateTilt({ ...motion.tilt, y: Number(event.target.value) })}
                step="1"
                type="range"
                value={Math.round(motion.tilt.y)}
              />
            </label>
          </div>
        </aside>

        <div className={styles.heroStage}>
          <PipelineView crown={crown} material={material} pipeline={pipeline} reduced={reduced} tilt={motion.tilt} />
          <div className={styles.readout}>
            <b>Pipeline {pipeline}</b>
            <span>{MATERIALS.find((entry) => entry.key === material)?.label}</span>
            <span>{sourceLabel}</span>
            <span>{Math.round(motion.tilt.x)}° / {Math.round(motion.tilt.y)}°</span>
          </div>
        </div>
      </section>

      <section className={styles.comparisonBand}>
        <header><span>A/B/C</span><h2>Mismo escudo, tres costes</h2></header>
        <div className={styles.pipelineGrid}>
          {PIPELINES.map((entry) => (
            <article className={pipeline === entry.key ? styles.activePipeline : ""} key={entry.key}>
              <div className={styles.miniPreview}>
                {entry.key === "C"
                  ? <LayeredShield crown="gold" material="gold" pipeline="A" reduced tilt={{ x: 0, y: 0 }} />
                  : <PipelineView crown="gold" material="gold" pipeline={entry.key} reduced tilt={{ x: 0, y: 0 }} />}
              </div>
              <strong>{entry.key} · {entry.label}</strong>
              <small>{entry.key === "A" ? "PNG/WebP transparente" : entry.key === "B" ? "8 vistas · sin WebGL" : "Geometría y materiales"}</small>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.materialBand}>
        <header><span>Materiales</span><h2>Marco y corona</h2></header>
        <div className={styles.materialRail}>
          {MATERIALS.map((entry) => (
            <article key={entry.key}>
              <LayeredShield crown="gold" material={entry.key} pipeline="A" reduced size={150} tilt={{ x: 0, y: 0 }} />
              <strong>{entry.label}</strong>
            </article>
          ))}
          <article>
            <LayeredShield crown="chrome" material="gold" pipeline="A" reduced size={150} tilt={{ x: 0, y: 0 }} />
            <strong>Corona cromo</strong>
          </article>
        </div>
      </section>

      <section className={styles.lodBand}>
        <header><span>LOD</span><h2>Lectura por tamaño</h2></header>
        <div className={styles.lodGrid}>
          <article><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={LOD_CONFIG} motion="reduced" size={24} /><small>24 · 2D</small></article>
          <article><TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={LOD_CONFIG} motion="reduced" size={32} /><small>32 · 2D</small></article>
          <article><LayeredShield crown="gold" material="gold" pipeline="B" reduced size={48} tilt={{ x: 0, y: 0 }} /><small>48 · render</small></article>
          <article><LayeredShield crown="gold" material="gold" pipeline="B" reduced size={64} tilt={{ x: 0, y: 0 }} /><small>64 · sprite</small></article>
          <article className={styles.mediumLod}><LayeredShield crown="gold" material="gold" pipeline="B" reduced size={120} tilt={{ x: 0, y: 0 }} /><small>Medio · sprite</small></article>
          <article className={styles.editorLod}><LayeredShield crown="gold" material="gold" pipeline="A" reduced size={180} tilt={{ x: 0, y: 0 }} /><small>Editor · GLB en vista principal</small></article>
        </div>
      </section>
    </main>
  );
}
