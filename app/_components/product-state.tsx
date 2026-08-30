import type { ReactNode } from "react";
import styles from "./product-state.module.css";

export type ProductStateKind =
  | "LOADING"
  | "EMPTY"
  | "NO_ACCESS"
  | "FEATURE_DISABLED"
  | "NOT_READY"
  | "STALE"
  | "OFFLINE"
  | "ERROR"
  | "SUCCESS"
  | "ACTION_REQUIRED"
  | "UNDER_REVIEW"
  | "SUSPENDED"
  | "ARCHIVED";

export function ProductState({
  actions,
  busy = false,
  description,
  eyebrow,
  state = "EMPTY",
  surface = "auto",
  technicalCode,
  title,
}: {
  actions?: ReactNode;
  busy?: boolean;
  description: string;
  eyebrow: string;
  state?: ProductStateKind;
  surface?: "auto" | "dark";
  technicalCode?: string;
  title: string;
}) {
  return (
    <section
      aria-busy={busy || undefined}
      className={styles.state}
      data-surface={surface}
      data-state={state}
      role={state === "ERROR" || state === "NO_ACCESS" || state === "SUSPENDED" ? "alert" : "status"}
    >
      <span className={styles.eyebrow}>{eyebrow}</span>
      <h2>{title}</h2>
      <p>{description}</p>
      {technicalCode ? <details className={styles.technical}><summary>Detalle técnico</summary><code>{technicalCode}</code></details> : null}
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </section>
  );
}

export function ProductFeedback({
  children,
  presentation = "inline",
  tone = "info",
}: {
  children: ReactNode;
  presentation?: "inline" | "toast";
  tone?: "danger" | "error" | "info" | "success" | "warning";
}) {
  return <p aria-live="polite" className={styles.feedback} data-presentation={presentation} data-tone={tone}>{children}</p>;
}
