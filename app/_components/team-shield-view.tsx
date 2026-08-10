import Image from "next/image";
import type { CSSProperties } from "react";
import { PLAYER_COSMETIC_MATERIALS } from "../player-cosmetics-catalog";
import { teamShieldCatalogEntry } from "../team-shield-cosmetics-catalog";
import type { TeamShieldConfig, TeamShieldRenderableItem } from "../team-shield-contract";
import {
  TEAM_SHIELD_PREMIUM_BALL_FRAMES,
  TEAM_SHIELD_PREMIUM_BORDER_TEXTURES,
} from "../team-shield-premium-assets";
import type { PremiumBallVisualState } from "../team-shield-premium-motion";
import styles from "./team-shield-view.module.css";

type ShieldStyle = CSSProperties & {
  "--shield-border-accent": string;
  "--shield-border-base": string;
  "--shield-border-highlight": string;
  "--shield-primary": string;
  "--shield-secondary": string;
  "--shield-size"?: string;
  "--shield-premium-texture"?: string;
  "--symbol-rotation": string;
  "--symbol-scale": number;
};

type PremiumBallStyle = CSSProperties & {
  "--premium-ball-light-x": string;
  "--premium-ball-light-y": string;
  "--premium-ball-tilt-x": string;
  "--premium-ball-tilt-y": string;
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

function materialKey(item: TeamShieldRenderableItem | null) {
  const key = item?.material ?? (typeof item?.render.material === "string" ? item.render.material : null);
  return key && key in PLAYER_COSMETIC_MATERIALS ? key : "pearl";
}

function SymbolGraphic({ kind, monogram }: { kind: string; monogram: string }) {
  if (kind === "monogram") return <strong className={styles.monogram}>{monogram.slice(0, 2)}</strong>;
  if (kind === "ball_iq") {
    return (
      <svg viewBox="0 0 64 64" aria-hidden="true">
        <circle cx="32" cy="32" r="25.5" />
        <path className={styles.solidSymbol} d="m32 18.5 9 6.5-3.5 10.5h-11L23 25Z" />
        <path d="m23 25-10.5 3.5M41 25l10.5 3.5M26.5 35.5 19 46m18.5-10.5L45 46M19 46l2.5 8M45 46l-2.5 8" />
      </svg>
    );
  }
  if (kind === "star_iq") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M32 5 38 23 57 20 43 33 55 49 36 42 32 60 28 42 9 49 21 33 7 20 26 23Z" /><path d="m32 20 6 12-6 12-6-12Z" /></svg>;
  }
  if (kind === "iq_star") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="m32 4 6.5 20.5L58 32l-19.5 7.5L32 60l-6.5-20.5L6 32l19.5-7.5Z" /><circle cx="32" cy="32" r="6.5" /></svg>;
  }
  if (kind === "bolt") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path className={styles.solidSymbol} d="M37 4 14 35h16l-4 25 24-34H34Z" /></svg>;
  }
  if (kind === "twin_bolt") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path className={styles.solidSymbol} d="M24 5 9 31h11l-3 21 16-27H23Zm18 7L31 34h9l-2 18 15-25h-9Z" /></svg>;
  }
  if (kind === "tower" || kind === "tower_elite") {
    return (
      <svg viewBox="0 0 64 64" aria-hidden="true">
        <path d="M14 57h36M19 57V23h8v-9h10v9h8v34M19 29h26M27 57V43h10v14" />
        <path d="M25 35h4m6 0h4" />
        {kind === "tower_elite" ? <path d="M13 17 18 7l8 5 6-8 6 8 8-5 5 10Z" /> : null}
      </svg>
    );
  }
  if (kind === "crown_iq") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M10 20 19 39 32 17l13 22 9-19-4 31H14Z" /><path d="M15 51h34M19 39h26" /></svg>;
  }
  if (kind === "nested_badge") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M10 8h44v27c0 11-9 19-22 24C19 54 10 46 10 35Z" /><path d="M20 18h24v16c0 6-5 11-12 15-7-4-12-9-12-15Z" /><path d="M32 23v20M25 30h14" /></svg>;
  }
  if (kind === "orbit_ball") {
    return <svg viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="9" /><path d="M7 32c0-9 11-16 25-16s25 7 25 16-11 16-25 16S7 41 7 32Z" /><path d="M21 8c8-4 20 4 27 17s6 27-2 31c-8 4-20-4-27-17S13 12 21 8Z" /><circle className={styles.solidSymbol} cx="54" cy="25" r="3" /></svg>;
  }
  return <svg viewBox="0 0 64 64" aria-hidden="true"><path d="M32 5 58 32 32 59 6 32Z" /><path d="m32 17 14 15-14 15-14-15Z" /></svg>;
}

function PremiumBallGraphic({
  motion,
  size,
}: {
  motion?: PremiumBallVisualState;
  size?: 24 | 32 | 48 | 64 | 82 | 210;
}) {
  if (size === 24 || size === 32) {
    return <span className={styles.premiumBallFallback} data-premium-lod="simplified-2d"><SymbolGraphic kind="ball_iq" monogram="" /></span>;
  }
  const frame = Math.max(0, Math.min(TEAM_SHIELD_PREMIUM_BALL_FRAMES.length - 1, motion?.frame ?? 4));
  const previousFrame = Math.max(0, Math.min(
    TEAM_SHIELD_PREMIUM_BALL_FRAMES.length - 1,
    motion?.previousFrame ?? frame,
  ));
  const transitioning = frame !== previousFrame;
  const blend = transitioning ? Math.max(0, Math.min(1, motion?.blend ?? 1)) : 1;
  const tiltX = motion?.tiltX ?? 0;
  const tiltY = motion?.tiltY ?? 0;
  const style: PremiumBallStyle = {
    "--premium-ball-light-x": `${50 + tiltX * 2.2}%`,
    "--premium-ball-light-y": `${42 + tiltY * 1.8}%`,
    "--premium-ball-tilt-x": `${tiltY * -0.42}deg`,
    "--premium-ball-tilt-y": `${tiltX * 0.42}deg`,
  };
  const sizes = size ? `${Math.max(24, Math.ceil(size * 0.36))}px` : "76px";

  return (
    <span
      className={styles.premiumBall}
      data-frame={frame}
      data-frame-count={TEAM_SHIELD_PREMIUM_BALL_FRAMES.length}
      data-premium-lod={size === 48 || size === 64 ? "prerender-static" : "multiview"}
      style={style}
    >
      {transitioning ? (
        <Image
          alt=""
          aria-hidden="true"
          className={styles.premiumBallFrame}
          fill
          loading="lazy"
          sizes={sizes}
          src={TEAM_SHIELD_PREMIUM_BALL_FRAMES[previousFrame]}
          style={{ opacity: 1 - blend }}
          unoptimized
        />
      ) : null}
      <Image
        alt=""
        aria-hidden="true"
        className={styles.premiumBallFrame}
        fill
        loading={motion ? "eager" : "lazy"}
        sizes={sizes}
        src={TEAM_SHIELD_PREMIUM_BALL_FRAMES[frame]}
        style={{ opacity: blend }}
        unoptimized
      />
      <span className={styles.premiumBallLight} aria-hidden="true" />
    </span>
  );
}

function OrnamentGraphic({ kind }: { kind: string }) {
  if (kind === "crown") return <svg viewBox="0 0 100 42" aria-hidden="true"><path d="m8 34 5-25 19 16L50 5l18 20L87 9l5 25Z" /><path d="M8 34h84v6H8Z" /><path d="M20 31h60" /></svg>;
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
  motion = "auto",
  premiumBallMotion,
  size,
}: {
  catalog?: readonly TeamShieldRenderableItem[];
  className?: string;
  config: TeamShieldConfig;
  label?: string;
  motion?: "auto" | "reduced";
  premiumBallMotion?: PremiumBallVisualState;
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
  const borderMaterial = materialKey(borderItem);
  const material = materialValue(borderItem);
  const premiumBorderEnabled = renderValue(borderItem, "premiumBorder", "") === "prerender-material-v1"
    && borderMaterial in TEAM_SHIELD_PREMIUM_BORDER_TEXTURES
    && size !== 24
    && size !== 32;
  const premiumBorderTexture = premiumBorderEnabled
    ? TEAM_SHIELD_PREMIUM_BORDER_TEXTURES[borderMaterial as keyof typeof TEAM_SHIELD_PREMIUM_BORDER_TEXTURES]
    : null;
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
    "--shield-premium-texture": premiumBorderTexture ? `url("${premiumBorderTexture}")` : undefined,
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
      data-material={borderMaterial}
      data-motion={motion}
      data-pattern={pattern}
      data-premium-border={premiumBorderEnabled}
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
          <span className={styles.primarySymbol} data-symbol={primarySymbol} aria-hidden="true">
            {primarySymbol === "ball_premium"
              ? <PremiumBallGraphic motion={motion === "reduced" ? undefined : premiumBallMotion} size={size} />
              : <SymbolGraphic kind={primarySymbol} monogram={selected.initials} />}
          </span>
          {selected.secondarySymbolKey ? <span className={styles.secondarySymbol} data-symbol={secondarySymbol} aria-hidden="true"><SymbolGraphic kind={secondarySymbol} monogram={selected.initials} /></span> : null}
          <strong className={styles.initials}>{selected.initials}</strong>
          {selected.foundationYear ? <small className={styles.foundationYear}>{selected.foundationYear}</small> : null}
          <span className={styles.effectLayer} aria-hidden="true" />
        </div>
      </div>
      {selected.topOrnamentKey ? <span className={styles.topOrnament} data-ornament={topOrnament}><OrnamentGraphic kind={topOrnament} /></span> : null}
      {selected.sideOrnamentKey ? <span className={styles.sideOrnament} data-ornament={sideOrnament}><OrnamentGraphic kind={sideOrnament} /></span> : null}
      {selected.bottomOrnamentKey ? <span className={styles.bottomOrnament} data-ornament={bottomOrnament}><OrnamentGraphic kind={bottomOrnament} /></span> : null}
    </div>
  );
}
