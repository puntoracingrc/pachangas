import Link from "next/link";
import type { ReactNode } from "react";
import styles from "../platform-admin.module.css";

export function PageHeader({
  actions,
  eyebrow = "Control Center",
  subtitle,
  title,
}: {
  actions?: ReactNode;
  eyebrow?: string;
  subtitle?: string;
  title: string;
}) {
  return (
    <header className={styles.pageHeader}>
      <div>
        <p>{eyebrow}</p>
        <h1>{title}</h1>
        {subtitle ? <span>{subtitle}</span> : null}
      </div>
      {actions ? <div className={styles.pageActions}>{actions}</div> : null}
    </header>
  );
}

export function MetricGrid({ children }: { children: ReactNode }) {
  return <section className={styles.metricGrid}>{children}</section>;
}

export function Metric({ hint, label, tone = "neutral", value }: { hint?: string; label: string; tone?: "danger" | "good" | "neutral" | "warning"; value: ReactNode }) {
  return (
    <article className={`${styles.metric} ${styles[`tone${tone}`]}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      {hint ? <small>{hint}</small> : null}
    </article>
  );
}

export function StatusBadge({ children, tone }: { children: ReactNode; tone?: "danger" | "good" | "info" | "muted" | "warning" }) {
  const resolved = tone ?? statusTone(String(children));
  return <span className={`${styles.statusBadge} ${styles[`status${resolved}`]}`}>{children}</span>;
}

export function statusTone(value: string): "danger" | "good" | "info" | "muted" | "warning" {
  const normalized = value.toLowerCase();
  if (/failed|error|critical|banned|unpaid|mismatch|rejected|cancel/.test(normalized)) return "danger";
  if (/active|confirmed|processed|finalized|product|sync ok|sent|resolved/.test(normalized)) return "good";
  if (/warning|pending|past_due|incomplete|suspended|investigating|trial/.test(normalized)) return "warning";
  if (/lab|info|open|proposed/.test(normalized)) return "info";
  return "muted";
}

export function Panel({ children, title, toolbar }: { children: ReactNode; title?: string; toolbar?: ReactNode }) {
  return (
    <section className={styles.panel}>
      {title || toolbar ? (
        <header className={styles.panelHeader}>
          {title ? <h2>{title}</h2> : <span />}
          {toolbar}
        </header>
      ) : null}
      {children}
    </section>
  );
}

export function DataTable({ children, label }: { children: ReactNode; label: string }) {
  return <div className={styles.tableScroll} role="region" aria-label={label} tabIndex={0}><table>{children}</table></div>;
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <p className={styles.emptyState}>{children}</p>;
}

export function Pagination({ page, pageSize, total, path, query = {} }: { page: number; pageSize: number; path: string; query?: Record<string, string | undefined>; total: number }) {
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const href = (nextPage: number) => {
    const params = new URLSearchParams();
    Object.entries(query).forEach(([key, value]) => { if (value) params.set(key, value); });
    params.set("page", String(nextPage));
    params.set("pageSize", String(pageSize));
    return `${path}?${params.toString()}`;
  };
  return (
    <nav className={styles.pagination} aria-label="Paginación">
      <span>{total.toLocaleString("es-ES")} registros · página {page} de {totalPages}</span>
      <div>
        {page > 1 ? <Link href={href(page - 1)}>Anterior</Link> : <span aria-disabled="true">Anterior</span>}
        {page < totalPages ? <Link href={href(page + 1)}>Siguiente</Link> : <span aria-disabled="true">Siguiente</span>}
      </div>
    </nav>
  );
}

export function Identifier({ value }: { value: string | null | undefined }) {
  return value ? <code className={styles.identifier} title={value}>{value.length > 16 ? `${value.slice(0, 8)}…${value.slice(-4)}` : value}</code> : <span className={styles.muted}>No disponible</span>;
}

export function Definition({ label, children }: { children: ReactNode; label: string }) {
  return <div className={styles.definition}><dt>{label}</dt><dd>{children}</dd></div>;
}

export function formatAdminDate(value: unknown, includeTime = true) {
  if (typeof value !== "string" || !value) return "No disponible";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "No disponible";
  return new Intl.DateTimeFormat("es-ES", includeTime
    ? { dateStyle: "medium", timeStyle: "short" }
    : { dateStyle: "medium" }).format(date);
}
