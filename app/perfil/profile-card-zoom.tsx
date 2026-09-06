"use client";

import { useEffect, useRef, useState, type ComponentProps } from "react";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import styles from "./profile-card-zoom.module.css";

export function ProfileCardZoom(props: ComponentProps<typeof PlayerCosmeticCard>) {
  const dialog = useRef<HTMLDialogElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    if (!open) return;
    const element = dialog.current;
    const previousOverflow = document.body.style.overflow;
    element?.showModal();
    document.body.style.overflow = "hidden";
    const resize = () => setScale(Math.min(1.8,
      (window.innerWidth - 40) / 260,
      (window.innerHeight - 112) / (card.current?.offsetHeight || 362)));
    resize();
    window.addEventListener("resize", resize);
    return () => {
      window.removeEventListener("resize", resize);
      document.body.style.overflow = previousOverflow;
      element?.close();
    };
  }, [open]);

  return (
    <div className={styles.root}>
      <button className={styles.trigger} type="button" aria-label="Ampliar mi carta" aria-haspopup="dialog" onClick={() => setOpen(true)}>
        <PlayerCosmeticCard {...props} />
      </button>
      <dialog ref={dialog} className={styles.dialog} aria-label="Mi carta ampliada" onClose={() => setOpen(false)} onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}>
        <button className={styles.close} type="button" aria-label="Cerrar carta ampliada" onClick={() => dialog.current?.close()}>×</button>
        <div ref={card} className={styles.card} style={{ zoom: scale }}>
          {open ? <PlayerCosmeticCard {...props} /> : null}
        </div>
      </dialog>
    </div>
  );
}
