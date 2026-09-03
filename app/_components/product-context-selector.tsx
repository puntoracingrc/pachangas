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

const productContextTypeLabels: Record<ProductContextOption["type"], string> = {
  club: "Club",
  competition: "Competición",
  platform: "Plataforma",
  profile: "Perfil",
  team: "Equipo",
};

export function productContextOptionLabel(context: ProductContextOption) {
  const seen = new Set<string>();
  return [
    context.title,
    productContextTypeLabels[context.type],
    context.role,
    context.detail,
    context.status,
    context.nextAction,
  ].flatMap((value) => {
    const label = value?.trim();
    const key = label?.toLocaleLowerCase("es");
    if (!label || !key || seen.has(key)) return [];
    seen.add(key);
    return [label];
  }).join(" · ");
}

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
  const activeLabel = productContextOptionLabel(active);

  return (
    <div className={styles.selector} data-context-type={active.type} aria-label={`Contexto activo: ${activeLabel}`}>
      <span className={styles.copy}>
        <small>{productContextTypeLabels[active.type]} · {active.role}</small>
        {contexts.length > 1 && onChange ? (
          <label>
            <span className={styles.srOnly}>Contexto activo</span>
            <select aria-label={`Contexto activo: ${activeLabel}`} title={activeLabel} value={active.id} onChange={(event) => onChange(event.target.value)}>
              {contexts.map((context) => <option key={context.id} value={context.id}>{productContextOptionLabel(context)}</option>)}
            </select>
          </label>
        ) : <strong title={activeLabel}>{active.title}</strong>}
        {active.detail ? <em title={active.detail}>{active.detail}</em> : null}
      </span>
      <span className={styles.meta}>
        {active.nextAction ? <small title={active.nextAction}>{active.nextAction}</small> : null}
        <b title={active.status ?? "Conectado"}>{active.status ?? "Conectado"}</b>
      </span>
    </div>
  );
}
