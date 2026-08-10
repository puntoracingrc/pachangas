import type { ComponentProps, CSSProperties } from "react";
import { PLAYER_COSMETIC_MATERIALS, catalogEntry, titleForLoadout } from "../player-cosmetics-catalog";
import type {
  PlayerCosmeticItem,
  PlayerCosmeticLoadout,
  PlayerFeaturedBadge,
} from "../player-cosmetics-contract";
import { PlayerCardView } from "./player-card-view";
import styles from "./player-cosmetic-card.module.css";

type PlayerCardViewProps = ComponentProps<typeof PlayerCardView>;

type PlayerCosmeticCardProps = PlayerCardViewProps & {
  cosmetics?: PlayerCosmeticItem[];
  featuredAchievement?: PlayerFeaturedBadge | null;
  loadout?: PlayerCosmeticLoadout | null;
};

type CosmeticStyle = CSSProperties & {
  "--player-cosmetic-accent"?: string;
  "--player-cosmetic-accent-highlight"?: string;
  "--player-cosmetic-frame"?: string;
};

function materialFor(key: string | null | undefined, cosmetics: PlayerCosmeticItem[]) {
  if (!key) return null;
  const owned = cosmetics.find((item) => item.key === key);
  const material = owned?.material ?? catalogEntry(key)?.material;
  return material && material in PLAYER_COSMETIC_MATERIALS
    ? PLAYER_COSMETIC_MATERIALS[material as keyof typeof PLAYER_COSMETIC_MATERIALS]
    : null;
}

export function PlayerCosmeticCard({
  className = "",
  cosmetics = [],
  featuredAchievement,
  featuredBadge,
  loadout,
  title,
  ...cardProps
}: PlayerCosmeticCardProps) {
  const frameMaterial = materialFor(loadout?.frameKey, cosmetics);
  const accentMaterial = materialFor(loadout?.accentKey, cosmetics);
  const cosmeticTitle = loadout ? titleForLoadout(loadout) : null;
  const cosmeticStyle: CosmeticStyle = {
    "--player-cosmetic-accent": accentMaterial?.base,
    "--player-cosmetic-accent-highlight": accentMaterial?.highlight,
    "--player-cosmetic-frame": frameMaterial?.base,
  };

  return (
    <div
      className={styles.stage}
      data-accent={loadout?.accentKey ?? "original"}
      data-background={loadout?.backgroundKey ?? "original"}
      data-effect={loadout?.effectKey ?? "none"}
      data-frame={loadout?.frameKey ?? "original"}
      style={cosmeticStyle}
    >
      <span className={styles.backgroundLayer} aria-hidden="true" />
      <PlayerCardView
        {...cardProps}
        className={`${className} ${styles.card}`.trim()}
        featuredBadge={featuredBadge ?? (featuredAchievement ? (
          <span className={styles.featuredBadge} title="Logro destacado">
            <span aria-hidden="true">★</span>
            {featuredAchievement.title}
          </span>
        ) : undefined)}
        title={title ?? (cosmeticTitle ? <span className={styles.playerTitle}>{cosmeticTitle}</span> : undefined)}
      />
      <span className={styles.effectLayer} aria-hidden="true" />
    </div>
  );
}
