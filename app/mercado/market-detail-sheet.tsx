"use client";

import type { ReactNode } from "react";
import styles from "./marketplace-v3d.module.css";

export function MarketDetailSheet({
  children,
  label,
  onClose,
}: {
  children: ReactNode;
  label: string;
  onClose: () => void;
}) {
  return (
    <aside className={styles.detailSheet} role="dialog" aria-modal="true" aria-label={label}>
      <button className={styles.detailClose} type="button" onClick={onClose} aria-label={`Cerrar ${label}`}>×</button>
      {children}
    </aside>
  );
}
