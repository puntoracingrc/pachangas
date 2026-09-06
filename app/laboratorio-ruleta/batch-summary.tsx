"use client";
import { useEffect, useRef, type CSSProperties } from "react";
import { catalogEntry } from "../player-cosmetics-catalog";
import { rewards, PrizePreview } from "../chest-lab-rewards";
import palettes from "../reward-rarity-visuals.json";
import type { Loot } from "./roulette";
import styles from "./page.module.css";

export type BatchSummaryData = { entries: { chest: { id: string | number; rarity: number }; loot: Loot }[]; points: number; previousPoints: number };
export function BatchSummary({ data, onAccept }: { data: BatchSummaryData; onAccept: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const accept = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const element = dialog.current;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    element?.showModal();
    accept.current?.focus({ preventScroll: true });
    return () => { element?.close(); document.body.style.overflow = previousOverflow; };
  }, []);
  return <dialog ref={dialog} className={styles.batchSummary} aria-labelledby="batch-title" onCancel={event => event.preventDefault()}>
    <header><span>TUS RECOMPENSAS</span><h2 id="batch-title">{data.entries.length} {data.entries.length === 1 ? "cofre abierto" : "cofres abiertos"}</h2><p>Estos son los premios que has conseguido.</p></header>
    <ul>{data.entries.map(({ chest, loot }) => {
      const cosmetic = catalogEntry(loot.key);
      const palette = palettes[rewards[chest.rarity].rarity];
      return <li key={chest.id} style={{ "--accent": palette.accent } as CSSProperties}>
        <div className={styles.batchPreview}><PrizePreview index={chest.rarity} prizeOverride={{ key: loot.duplicate ? null : loot.key, points: loot.points, color: palette.accent }}/></div>
        <div><small>{palette.label}</small><h3>{cosmetic && !loot.duplicate ? cosmetic.name : `+${loot.points} puntos`}</h3><p>{loot.duplicate ? `${cosmetic?.name} repetido · convertido en puntos` : cosmetic ? `Nuevo en tu colección${loot.points ? ` · +${loot.points} puntos` : ""}` : "Premio de puntos"}</p></div>
      </li>;
    })}</ul>
    <footer>{data.previousPoints > 0 && <p>Además, ya habías conseguido {data.previousPoints} puntos en los cofres anteriores.</p>}<strong>+{data.points + data.previousPoints} puntos en total</strong><button ref={accept} className={styles.primary} onClick={onAccept}>Aceptar y volver a la ruleta</button></footer>
  </dialog>;
}
