"use client";

import styles from "./product-context-selector.module.css";

export type ProductContextOption = {
  detail?: string;
  id: string;
  nextAction?: string;
  role: string;
  status?: string;
  title: string;
  type: "club" | "competition" | "platform" | "profile" | "team";
};

export function ProductContextSelector({
  activeId,
  contexts,
  onChange,
}: {
  activeId: string;
  contexts: ProductContextOption[];
  onChange?: (id: string) => void;
}) {
  const active = contexts.find(({ id }) => id === activeId) ?? contexts[0];
  if (!active) return null;

  return (
    <div className={styles.selector} data-context-type={active.type}>
      <span className={styles.copy}>
        <small>{active.type} · {active.role}</small>
        {contexts.length > 1 && onChange ? (
          <label>
            <span className={styles.srOnly}>Contexto activo</span>
            <select aria-label="Contexto activo" value={active.id} onChange={(event) => onChange(event.target.value)}>
              {contexts.map((context) => <option key={context.id} value={context.id}>{context.title}</option>)}
            </select>
          </label>
        ) : <strong>{active.title}</strong>}
        {active.detail ? <em>{active.detail}</em> : null}
      </span>
      <span className={styles.meta}>
        {active.nextAction ? <small>{active.nextAction}</small> : null}
        <b>{active.status ?? "Conectado"}</b>
      </span>
    </div>
  );
}
