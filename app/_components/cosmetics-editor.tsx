import type { CSSProperties, ReactNode } from "react";
import { PLAYER_COSMETIC_RARITY_LABELS, PLAYER_COSMETIC_SLOT_LABELS } from "../player-cosmetics-catalog";
import type { PlayerCosmeticItem, PlayerCosmeticSlot } from "../player-cosmetics-contract";
import styles from "./cosmetics-editor.module.css";

export type CosmeticEditorOption = {
  key: string;
  material?: string | null;
  meta?: string;
  name: string;
  new?: boolean;
};

export function CosmeticEditorShell({
  actions,
  children,
  className = "",
  preview,
}: {
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
  preview: ReactNode;
}) {
  return (
    <section className={`${styles.shell} ${className}`.trim()}>
      <div className={styles.controls}>{children}</div>
      <div className={styles.preview}>{preview}</div>
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </section>
  );
}

export function CosmeticCategoryTabs({
  active,
  counts,
  onChange,
}: {
  active: PlayerCosmeticSlot | "badge";
  counts: Record<PlayerCosmeticSlot | "badge", number>;
  onChange: (slot: PlayerCosmeticSlot | "badge") => void;
}) {
  const tabs: Array<PlayerCosmeticSlot | "badge"> = ["frame", "background", "accent", "effect", "title", "badge"];
  return (
    <nav className={styles.tabs} aria-label="Partes de la ficha">
      {tabs.map((slot) => (
        <button
          aria-pressed={active === slot}
          className={active === slot ? styles.activeTab : ""}
          key={slot}
          type="button"
          onClick={() => onChange(slot)}
        >
          <span>{slot === "badge" ? "Logro" : PLAYER_COSMETIC_SLOT_LABELS[slot]}</span>
          {counts[slot] > 0 ? <NewBadge count={counts[slot]} /> : null}
        </button>
      ))}
    </nav>
  );
}

export function CosmeticCategoryNav<T extends string>({
  active,
  ariaLabel,
  items,
  onChange,
}: {
  active: T;
  ariaLabel: string;
  items: Array<{ count?: number; key: T; label: string }>;
  onChange: (key: T) => void;
}) {
  return (
    <nav className={styles.tabs} aria-label={ariaLabel}>
      {items.map((item) => (
        <button
          aria-pressed={active === item.key}
          className={active === item.key ? styles.activeTab : ""}
          key={item.key}
          type="button"
          onClick={() => onChange(item.key)}
        >
          <span>{item.label}</span>
          {item.count ? <NewBadge count={item.count} /> : null}
        </button>
      ))}
    </nav>
  );
}

export function NewBadge({ count }: { count?: number }) {
  return <small className={styles.newBadge}>{typeof count === "number" ? count : "Nuevo"}</small>;
}

export function OwnedCosmeticSelector({
  items,
  noneLabel,
  onChange,
  selectedKey,
}: {
  items: PlayerCosmeticItem[];
  noneLabel: string;
  onChange: (key: string | null) => void;
  selectedKey: string | null;
}) {
  return (
    <div className={styles.optionGrid}>
      <button className={selectedKey === null ? styles.selectedOption : ""} type="button" onClick={() => onChange(null)}>
        <span className={styles.originalPreview}>IQ</span>
        <strong>{noneLabel}</strong>
      </button>
      {items.map((item) => (
        <button
          className={selectedKey === item.key ? styles.selectedOption : ""}
          key={item.key}
          type="button"
          onClick={() => onChange(item.key)}
        >
          <MaterialSwatch material={item.material} />
          <strong>{item.name}</strong>
          <small>{PLAYER_COSMETIC_RARITY_LABELS[item.rarity]}</small>
          {!item.seenAt ? <NewBadge /> : null}
        </button>
      ))}
    </div>
  );
}

export function CosmeticOptionSelector({
  items,
  noneLabel,
  onChange,
  selectedKeys,
}: {
  items: CosmeticEditorOption[];
  noneLabel?: string;
  onChange: (key: string | null) => void;
  selectedKeys: string[];
}) {
  return (
    <div className={styles.optionGrid}>
      {noneLabel ? (
        <button className={!selectedKeys.length ? styles.selectedOption : ""} type="button" onClick={() => onChange(null)}>
          <span className={styles.originalPreview}>IQ</span>
          <strong>{noneLabel}</strong>
        </button>
      ) : null}
      {items.map((item) => (
        <button
          className={selectedKeys.includes(item.key) ? styles.selectedOption : ""}
          key={item.key}
          type="button"
          onClick={() => onChange(item.key)}
        >
          <MaterialSwatch material={item.material ?? null} />
          <strong>{item.name}</strong>
          {item.meta ? <small>{item.meta}</small> : null}
          {item.new ? <NewBadge /> : null}
        </button>
      ))}
    </div>
  );
}

export function MaterialSwatch({ color, material }: { color?: string | null; material: string | null }) {
  const style = {
    "--swatch-color": color ?? "transparent",
    "--swatch-material": material ?? "original",
  } as CSSProperties;
  return <span className={styles.materialSwatch} data-material={material ?? "original"} style={style} aria-hidden="true" />;
}

export function EditorActions({
  busy = false,
  primaryDisabled = false,
  primaryLabel,
  onPrimary,
  onReset,
  resetLabel = "Restablecer",
}: {
  busy?: boolean;
  onPrimary: () => void;
  onReset: () => void;
  primaryDisabled?: boolean;
  primaryLabel: string;
  resetLabel?: string;
}) {
  return (
    <div className={styles.editorActions}>
      <button type="button" disabled={busy} onClick={onReset}>{resetLabel}</button>
      <button className={styles.primaryAction} type="button" disabled={busy || primaryDisabled} onClick={onPrimary}>
        {primaryLabel}
      </button>
    </div>
  );
}

export function UnsavedChanges({ dirty, synchronizedLabel = "Ficha sincronizada" }: { dirty: boolean; synchronizedLabel?: string }) {
  return (
    <span className={`${styles.unsaved} ${dirty ? styles.unsavedActive : ""}`} aria-live="polite">
      {dirty ? "Cambios sin guardar" : synchronizedLabel}
    </span>
  );
}
