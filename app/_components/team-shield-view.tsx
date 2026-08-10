import type { CSSProperties } from "react";
import { PLAYER_COSMETIC_MATERIALS } from "../player-cosmetics-catalog";
import { teamShieldCatalogEntry } from "../team-shield-cosmetics-catalog";
import type { TeamShieldConfig, TeamShieldRenderableItem } from "../team-shield-contract";
import styles from "./team-shield-view.module.css";

type ShieldStyle = CSSProperties & {
  "--shield-border-accent": string;
  "--shield-border-base": string;
  "--shield-border-highlight": string;
  "--shield-primary": string;
  "--shield-secondary": string;
  "--shield-size"?: string;
  "--symbol-rotation": string;
  "--symbol-scale": number;
};

function findItem(catalog: readonly TeamShieldRenderableItem[], key: string | null | undefined) {
  return key ? catalog.find((item) => item.key === key) ?? teamShieldCatalogEntry(key) : null;
}

function renderValue(item: TeamShieldRenderableItem | null, key: string, fallback: string) {
  return typeof item?.render[key] === "string" ? item.render[key] as string : fallback;
}

function colorValue(catalog: readonly TeamShieldRenderableItem[], key: string, fallback: string) {
  const item = findItem(catalog, key);
  return typeof item?.render.hex === "string" ? item.render.hex : fallback;
}

function materialValue(item: TeamShieldRenderableItem | null) {
  const materialKey = item?.material ?? (typeof item?.render.material === "string" ? item.render.material : null);
  return materialKey && materialKey in PLAYER_COSMETIC_MATERIALS
    ? PLAYER_COSMETIC_MATERIALS[materialKey as keyof typeof PLAYER_COSMETIC_MATERIALS]
    : PLAYER_COSMETIC_MATERIALS.pearl;
}

function SymbolGraphic({ kind, monogram }: { kind: string; monogram: string }) {
  if (kind === "monogram") return <strong className={styles.monogram}>{monogram.slice(0, 2)}</strong>;
  if (kind === "ball_iq") {
    return (
      <svg viewBox="0 0 64 64" aria-hidden="true">
        <circle cx="32" cy="32" r="25" />
        <path d="m32 18 9 7-4 11H27l-4-11 9-7Zm-9 7-11 3m30-3 10 3M27 36l-8 10m18-10 8 10M19 46l2 8m24-8-2 8" />
      </svg>
    );
  }
  if (kind === "star_iq" || kind === "iq_star") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M32 5 38 23 57 20 43 33 55 49 36 42 32 60 28 42 9 49 21 33 7 20 26 23Z" /></svg>;
  }
  if (kind === "bolt") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M37 4 14 35h16l-4 25 24-34H34Z" /></svg>;
  }
  if (kind === "twin_bolt") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M24 5 9 31h11l-3 21 16-27H23Zm18 7L31 34h9l-2 18 15-25h-9Z" /></svg>;
  }
  if (kind === "tower" || kind === "tower_elite") {
    return (
      <svg viewBox="0 0 64 64" aria-hidden="true">
        <path d="M15 57h34M20 57V22h6v-8h7v8h6v-8h7v43M20 27h26M27 57V43h10v14" />
        {kind === "tower_elite" ? <path d="M13 10h38L45 4H19Z" /> : null}
      </svg>
    );
  }
  return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M32 5 58 32 32 59 6 32Z" /></svg>;
}

function OrnamentGraphic({ kind }: { kind: string }) {
  if (kind === "crown") return <svg viewBox="0 0 100 42" aria-hidden="true"><path d="m8 35 4-27 20 17L50 4l18 21L88 8l4 27Z" /><path d="M8 35h84v5H8Z" /></svg>;
  if (kind === "three_stars") return <span className={styles.stars}>★ ★ ★</span>;
  if (kind === "laurels") return <svg viewBox="0 0 150 100" aria-hidden="true"><path d="M57 92C26 76 13 50 18 13M93 92c31-16 44-42 39-79" /><path d="M20 26 5 17m17 24L6 36m21 20L9 54m28 18-17 2m110-48 15-9m-17 24 16-5m-21 20 18-2m-28 18 17 2" /></svg>;
  if (kind === "wings") return <svg viewBox="0 0 160 76" aria-hidden="true"><path d="M70 55C45 51 23 40 5 12c26 3 46 11 60 25M90 55c25-4 47-15 65-43-26 3-46 11-60 25M14 23l42 20M146 23l-42 20" /></svg>;
  if (kind === "side_bolts") return <svg viewBox="0 0 160 80" aria-hidden="true"><path d="M35 5 7 44h21l-6 31 34-47H34ZM125 5l28 39h-21l6 31-34-47h22Z" /></svg>;
  if (kind === "plate") return <span className={styles.plate}>IQ TEAM</span>;
  return <span className={styles.banner}>PACHANGAS IQ</span>;
}

export function TeamShieldView({
  catalog = [],
  className = "",
  config,
  label,
  size,
}: {
  catalog?: readonly TeamShieldRenderableItem[];
  className?: string;
  config: TeamShieldConfig;
  label?: string;
  size?: 24 | 32 | 48 | 64 | 82 | 210;
}) {
  const selected = config;
  const shape = renderValue(findItem(catalog, selected.shapeKey), "shape", "classic_iq");
  const background = renderValue(findItem(catalog, selected.backgroundKey), "background", "duotone");
  const pattern = renderValue(findItem(catalog, selected.patternKey), "pattern", "none");
  const primarySymbol = renderValue(findItem(catalog, selected.primarySymbolKey), "symbol", "ball_iq");
  const secondarySymbol = renderValue(findItem(catalog, selected.secondarySymbolKey), "symbol", "none");
  const borderItem = findItem(catalog, selected.borderKey);
  const border = renderValue(borderItem, "border", "clean");
  const material = materialValue(borderItem);
  const effect = renderValue(findItem(catalog, selected.effectKey), "effect", "none");
  const topOrnament = renderValue(findItem(catalog, selected.topOrnamentKey), "ornament", "none");
  const sideOrnament = renderValue(findItem(catalog, selected.sideOrnamentKey), "ornament", "none");
  const bottomOrnament = renderValue(findItem(catalog, selected.bottomOrnamentKey), "ornament", "none");
  const style: ShieldStyle = {
    "--shield-border-accent": material.accent,
    "--shield-border-base": material.base,
    "--shield-border-highlight": material.highlight,
    "--shield-primary": colorValue(catalog, selected.primaryColorKey, "#071b31"),
    "--shield-secondary": colorValue(catalog, selected.secondaryColorKey, "#33d6dd"),
    "--shield-size": size ? `${size}px` : undefined,
    "--symbol-rotation": `${selected.primarySymbolRotation}deg`,
    "--symbol-scale": selected.primarySymbolScale,
  };

  return (
    <div
      aria-label={label ?? `Escudo ${selected.initials}`}
      className={`${styles.stage} ${className}`.trim()}
      data-background={background}
      data-border={border}
      data-effect={effect}
      data-pattern={pattern}
      data-shape={shape}
      data-size={size ?? "fluid"}
      role="img"
      style={style}
    >
      <div className={styles.shieldBody}>
        <div className={styles.shieldFace}>
          <span className={styles.backgroundLayer} aria-hidden="true" />
          <span className={styles.patternLayer} aria-hidden="true" />
          <span className={styles.innerLine} aria-hidden="true" />
          <span className={styles.primarySymbol} aria-hidden="true"><SymbolGraphic kind={primarySymbol} monogram={selected.initials} /></span>
          {selected.secondarySymbolKey ? <span className={styles.secondarySymbol} aria-hidden="true"><SymbolGraphic kind={secondarySymbol} monogram={selected.initials} /></span> : null}
          <strong className={styles.initials}>{selected.initials}</strong>
          {selected.foundationYear ? <small className={styles.foundationYear}>{selected.foundationYear}</small> : null}
          <span className={styles.effectLayer} aria-hidden="true" />
        </div>
      </div>
      {selected.topOrnamentKey ? <span className={styles.topOrnament}><OrnamentGraphic kind={topOrnament} /></span> : null}
      {selected.sideOrnamentKey ? <span className={styles.sideOrnament}><OrnamentGraphic kind={sideOrnament} /></span> : null}
      {selected.bottomOrnamentKey ? <span className={styles.bottomOrnament}><OrnamentGraphic kind={bottomOrnament} /></span> : null}
    </div>
  );
}
