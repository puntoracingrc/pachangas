"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import styles from "./official-market-game-view.module.css";

export type OfficialMarketTab = {
  id: string;
  label: string;
  onSelect: () => void;
};

export function OfficialMarketGameView({
  actions,
  activeTab,
  adminHref,
  children,
  context,
  filters,
  search,
  tabs,
  title,
}: {
  actions?: ReactNode;
  activeTab: string;
  adminHref?: string;
  children: ReactNode;
  context?: ReactNode;
  filters?: ReactNode;
  search?: ReactNode;
  tabs: OfficialMarketTab[];
  title: string;
}) {
  return (
    <div className={styles.layout} data-official-market-view="v2.1">
      <nav className={styles.subnav} aria-label="Secciones del mercado" data-official-market-navigation="single">
        <div>
          {tabs.map((tab) => (
            <button
              aria-current={activeTab === tab.id ? "page" : undefined}
              className={activeTab === tab.id ? `${styles.active} active` : ""}
              key={tab.id}
              type="button"
              onClick={tab.onSelect}
            >
              {tab.label}
            </button>
          ))}
        </div>
        {adminHref ? <Link className={styles.adminLink} href={adminHref}>Configurar partido</Link> : null}
      </nav>

      <section className={styles.workspace}>
        <header className={styles.titlebar}>
          <div><span>Mercado</span><h1>{title}</h1></div>
          {actions ? <div className={styles.actions}>{actions}</div> : null}
        </header>
        {context ? <div className={styles.context}>{context}</div> : null}
        {search ? <div className={styles.search}>{search}</div> : null}
        {filters ? <div className={styles.filters}>{filters}</div> : null}
        <div className={styles.results}>{children}</div>
      </section>
    </div>
  );
}
