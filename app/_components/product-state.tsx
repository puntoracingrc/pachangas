import type { ReactNode } from "react";
import styles from "./product-state.module.css";

export function ProductState({
  actions,
  busy = false,
  description,
  eyebrow,
  surface = "auto",
  title,
}: {
  actions?: ReactNode;
  busy?: boolean;
  description: string;
  eyebrow: string;
  surface?: "auto" | "dark";
  title: string;
}) {
  return (
    <section
      aria-busy={busy || undefined}
      className={styles.state}
      data-surface={surface}
      role="status"
    >
      <span className={styles.eyebrow}>{eyebrow}</span>
      <h2>{title}</h2>
      <p>{description}</p>
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </section>
  );
}

export function ProductFeedback({
  children,
  tone = "info",
}: {
  children: ReactNode;
  tone?: "error" | "info" | "success";
}) {
  return <p aria-live="polite" className={styles.feedback} data-tone={tone}>{children}</p>;
}
