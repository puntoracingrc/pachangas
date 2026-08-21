import type { ReactNode } from "react";
import styles from "./official-ui-v2-primitives.module.css";

export function GamePageHeader({ actions, eyebrow, summary, title }: { actions?: ReactNode; eyebrow: string; summary?: string; title: string }) {
  return <header className={styles.pageHeader}><div><span>{eyebrow}</span><h1>{title}</h1>{summary ? <p>{summary}</p> : null}</div>{actions ? <div className={styles.actions}>{actions}</div> : null}</header>;
}

export function StatusChip({ children, tone = "neutral" }: { children: ReactNode; tone?: "danger" | "info" | "neutral" | "success" | "warning" }) {
  return <span className={styles.statusChip} data-tone={tone}>{children}</span>;
}

export function MetricTile({ label, value }: { label: string; value: ReactNode }) {
  return <div className={styles.metric}><span>{label}</span><strong>{value}</strong></div>;
}

export function SectionHeader({ action, eyebrow, title }: { action?: ReactNode; eyebrow?: string; title: string }) {
  return <header className={styles.sectionHeader}><div>{eyebrow ? <span>{eyebrow}</span> : null}<h2>{title}</h2></div>{action}</header>;
}

export function PrimaryActionCard({ action, children, title }: { action?: ReactNode; children: ReactNode; title: string }) {
  return <section className={styles.primaryCard}><h2>{title}</h2><div>{children}</div>{action ? <footer>{action}</footer> : null}</section>;
}

export function SecondaryActionCard({ children, title }: { children: ReactNode; title: string }) {
  return <section className={styles.secondaryCard}><h2>{title}</h2>{children}</section>;
}

export function GameTabs({ active, items }: { active: string; items: Array<{ href: string; id: string; label: string }> }) {
  return <nav className={styles.tabs} aria-label="Secciones"><span>Partido</span>{items.map((item) => <a aria-current={active === item.id ? "page" : undefined} href={item.href} key={item.id}>{item.label}</a>)}</nav>;
}

export function CompactList({ children, label }: { children: ReactNode; label: string }) {
  return <div className={styles.compactList} aria-label={label}>{children}</div>;
}

export function ActivityFeed({ children }: { children: ReactNode }) {
  return <div className={styles.activityFeed}>{children}</div>;
}

export function ResponsiveActionBar({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`${styles.actionBar}${className ? ` ${className}` : ""}`}>{children}</div>;
}
