"use client";

import type { ReactNode } from "react";
import styles from "./official-match-game-hub.module.css";

export type OfficialMatchHubPane = {
  id: string;
  label: string;
};

export function OfficialMatchGameHub({
  activePane,
  back,
  context,
  onSelectPane,
  panes,
  share,
  tools,
}: {
  activePane: string;
  back?: ReactNode;
  context: {
    date: string;
    finalized?: boolean;
    kind: string;
    label: string;
    place: string;
    status: ReactNode;
    title: string;
  };
  onSelectPane: (pane: string) => void;
  panes: OfficialMatchHubPane[];
  share?: ReactNode;
  tools?: ReactNode;
}) {
  return (
    <>
      <nav
        className={`${styles.subnav} match-manager-subnav`}
        aria-label="Secciones del partido"
        data-official-match-navigation="single"
      >
        {back ? <div className={styles.back}>{back}</div> : null}
        <div className={styles.panes}>
          {panes.map((pane) => (
            <button
              aria-current={activePane === pane.id ? "page" : undefined}
              className={activePane === pane.id ? `${styles.active} active` : ""}
              key={pane.id}
              onClick={() => onSelectPane(pane.id)}
              type="button"
            >
              <span>{pane.label}</span>
            </button>
          ))}
        </div>
        {tools ? <div className={styles.tools}>{tools}</div> : null}
        {share ? <div className={styles.share}>{share}</div> : null}
      </nav>

      <header
        className={`${styles.context} match-active-context${context.finalized ? ` ${styles.finalized} finalized` : ""}`}
        aria-label="Contexto del partido activo"
        data-official-match-context="persistent"
      >
        <div className={styles.contextCopy}>
          <span>{context.label}</span>
          <strong>{context.title}</strong>
          <small>{context.date} · {context.place || "Campo por confirmar"}</small>
        </div>
        <b className={styles.kind}>{context.kind}</b>
        <div className={styles.status}>{context.status}</div>
      </header>
    </>
  );
}
