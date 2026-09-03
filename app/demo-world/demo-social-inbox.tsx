"use client";

import { useMemo, useState } from "react";
import type { DemoWorldNotification, DemoWorldPrimaryTab } from "./demo-world-contract";
import styles from "./demo-social-inbox.module.css";

export type DemoSocialInboxAction = {
  context: string;
  id: string;
  resolved: boolean;
  summary: string;
  targetTab: "equipo" | "partido" | "retos";
  title: string;
  type: "challenge" | "match" | "team";
};

export type DemoSocialInboxState = {
  archivedIds: string[];
  readIds: string[];
  resolvedActionIds: string[];
};

type DemoInboxItem = {
  actionRequired: boolean;
  context: string;
  id: string;
  occurredAt: string;
  resolved: boolean;
  summary: string;
  targetTab: DemoWorldPrimaryTab;
  title: string;
  type: "challenge" | "market" | "match" | "team";
};

const socialCategories = new Set(["challenge", "group", "market", "match"]);

function informationItems(notifications: DemoWorldNotification[]): DemoInboxItem[] {
  return notifications
    .filter((item) => socialCategories.has(item.category))
    .map((item) => ({
      actionRequired: false,
      context: item.category === "challenge" ? "Retos" : item.category === "group" ? "Equipo" : item.category === "market" ? "Mercado" : "Partidos",
      id: item.id,
      occurredAt: item.createdAt,
      resolved: true,
      summary: item.body,
      targetTab: item.category === "challenge" ? "retos" : item.targetTab,
      title: item.title,
      type: item.category === "group" ? "team" : item.category === "challenge" ? "challenge" : item.category === "market" ? "market" : "match",
    }));
}

function relativeDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Actividad reciente";
  return new Intl.DateTimeFormat("es-ES", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }).format(date);
}

function TypeIcon({ type }: { type: DemoInboxItem["type"] }) {
  if (type === "match") return <span aria-hidden="true">PA</span>;
  if (type === "challenge") return <span aria-hidden="true">RE</span>;
  if (type === "market") return <span aria-hidden="true">ME</span>;
  return <span aria-hidden="true">EQ</span>;
}

export function DemoSocialInbox({
  actions,
  notifications,
  onBack,
  onOpen,
  onStateChange,
  state,
}: {
  actions: DemoSocialInboxAction[];
  notifications: DemoWorldNotification[];
  onBack: () => void;
  onOpen: (tab: DemoWorldPrimaryTab, itemId: string) => void;
  onStateChange: (state: DemoSocialInboxState) => void;
  state: DemoSocialInboxState;
}) {
  const [view, setView] = useState<"all" | "pending">("pending");
  const [filter, setFilter] = useState<"all" | DemoInboxItem["type"]>("all");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [offline, setOffline] = useState(false);
  const [message, setMessage] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const items = useMemo<DemoInboxItem[]>(() => [
    ...actions.map((item, index) => ({
      actionRequired: !item.resolved,
      context: item.context,
      id: item.id,
      occurredAt: new Date(Date.UTC(2027, 2, 20 - index, 18, 30)).toISOString(),
      resolved: item.resolved,
      summary: item.summary,
      targetTab: item.targetTab,
      title: item.title,
      type: item.type,
    })),
    ...informationItems(notifications),
  ], [actions, notifications]);

  const readSet = new Set(state.readIds);
  const archivedSet = new Set(state.archivedIds);
  const pendingCount = items.filter((item) => item.actionRequired && !item.resolved).length;
  const unreadCount = items.filter((item) => !readSet.has(item.id)).length;
  const filtered = items.filter((item) => {
    if (filter !== "all" && item.type !== filter) return false;
    if (view === "pending") return item.actionRequired && !item.resolved;
    return !archivedSet.has(item.id) || (item.actionRequired && !item.resolved);
  });
  const selected = filtered.find((item) => item.id === selectedId) ?? filtered[0] ?? null;

  function update(next: DemoSocialInboxState, success: string) {
    if (offline) {
      setMessage("Necesitas conexión para confirmar esta acción.");
      return;
    }
    onStateChange(next);
    setMessage(success);
  }

  function toggleRead(item: DemoInboxItem) {
    const readIds = readSet.has(item.id) ? state.readIds.filter((id) => id !== item.id) : [...new Set([...state.readIds, item.id])];
    update({ ...state, readIds }, readSet.has(item.id) ? "Aviso marcado como no leído." : "Aviso marcado como leído.");
  }

  function archive(item: DemoInboxItem) {
    update({ ...state, archivedIds: [...new Set([...state.archivedIds, item.id])] }, item.actionRequired && !item.resolved ? "Actividad archivada. La acción sigue en Pendientes." : "Actividad archivada.");
  }

  function open(item: DemoInboxItem) {
    if (!readSet.has(item.id)) onStateChange({ ...state, readIds: [...new Set([...state.readIds, item.id])] });
    onOpen(item.targetTab, item.id);
  }

  const renderItem = (item: DemoInboxItem) => {
    const unread = !readSet.has(item.id);
    return (
      <article className={styles.item} data-selected={selected?.id === item.id || undefined} data-state={item.resolved ? "resolved" : item.actionRequired ? "pending" : "information"} key={item.id} onClick={() => setSelectedId(item.id)}>
        <TypeIcon type={item.type} />
        <div className={styles.copy}>
          <div><strong>{item.title}</strong>{unread ? <i>Nuevo</i> : null}</div>
          <p>{item.summary}</p>
          <small>{item.context} · {relativeDate(item.occurredAt)}</small>
        </div>
        <button className={styles.primary} type="button" onClick={(event) => { event.stopPropagation(); open(item); }}>{item.actionRequired && !item.resolved ? "Revisar" : "Abrir"}</button>
        <details className={styles.menu} onClick={(event) => event.stopPropagation()}>
          <summary aria-label={`Más opciones para ${item.title}`}>⋮</summary>
          <div><button type="button" onClick={() => toggleRead(item)}>{unread ? "Marcar como leído" : "Marcar como no leído"}</button><button type="button" onClick={() => archive(item)}>Archivar</button></div>
        </details>
      </article>
    );
  };

  return (
    <section className={styles.page} data-demo-social-inbox="local-only" data-offline={offline || undefined}>
      <header className={styles.header}>
        <div><span>Mundo Demo · Bandeja social</span><h1>Avisos</h1><p>{pendingCount ? `${pendingCount} ${pendingCount === 1 ? "acción necesita" : "acciones necesitan"} tu atención` : "No tienes acciones pendientes"}</p></div>
        <div><button type="button" onClick={onBack}>Volver</button><button type="button" aria-pressed={offline} onClick={() => { setOffline((value) => !value); setMessage(offline ? "Conexión Demo restaurada." : "Modo sin conexión: solo lectura."); }}>{offline ? "Reconectar" : "Probar offline"}</button></div>
      </header>

      <div className={styles.toolbar}>
        <div role="tablist" aria-label="Vista de avisos"><button aria-selected={view === "pending"} role="tab" type="button" onClick={() => setView("pending")}>Pendientes <b>{pendingCount}</b></button><button aria-selected={view === "all"} role="tab" type="button" onClick={() => setView("all")}>Todos <b>{unreadCount}</b></button></div>
        <div><button type="button" aria-expanded={filtersOpen} onClick={() => setFiltersOpen((value) => !value)}>Filtrar</button><button type="button" onClick={() => setSettingsOpen((value) => !value)}>Ajustes</button><button type="button" disabled={offline || unreadCount === 0} onClick={() => update({ ...state, readIds: items.map((item) => item.id) }, "Todos los avisos visibles se han marcado como leídos.")}>Marcar todo leído</button></div>
      </div>

      {filtersOpen ? <div className={styles.filters} aria-label="Filtrar por tipo">{(["all", "match", "challenge", "market", "team"] as const).map((value) => <button aria-pressed={filter === value} key={value} type="button" onClick={() => setFilter(value)}>{value === "all" ? "Todos" : value === "match" ? "Partidos" : value === "challenge" ? "Retos" : value === "market" ? "Mercado" : "Equipo"}</button>)}</div> : null}
      {settingsOpen ? <aside className={styles.settings}><div><span>Ajustes de notificaciones</span><strong>Preferencias separadas de la bandeja</strong><p>En producción viven en Ajustes. Push y correo siguen desactivados por ahora.</p></div><dl><div><dt>En la app</dt><dd>Activo</dd></div><div><dt>Push</dt><dd>OFF</dd></div><div><dt>Correo</dt><dd>OFF</dd></div></dl></aside> : null}
      {offline ? <p className={styles.offline} role="status">Resultados guardados · última actualización confirmada · las escrituras están bloqueadas</p> : null}
      {message ? <p className={styles.message} aria-live="polite">{message}</p> : null}

      <div className={styles.layout}>
        <div className={styles.list}>
          {filtered.length ? <>{view === "pending" ? <h2>Necesita tu atención</h2> : <h2>Actividad reciente</h2>}{filtered.map(renderItem)}</> : <div className={styles.empty}><strong>{view === "pending" ? "Todo al día" : "No hay actividad en este filtro"}</strong><p>{view === "pending" ? "Las acciones resueltas permanecen disponibles en Todos." : "Prueba otro filtro o reinicia el Mundo Demo."}</p></div>}
          {view === "all" && filtered.length >= 8 ? <button className={styles.older} type="button">Ver anteriores</button> : null}
        </div>
        <aside className={styles.detail} aria-label="Detalle del aviso">
          {selected ? <><TypeIcon type={selected.type} /><span>{selected.context}</span><h2>{selected.title}</h2><p>{selected.summary}</p><small>{relativeDate(selected.occurredAt)}</small><button type="button" onClick={() => open(selected)}>{selected.actionRequired && !selected.resolved ? "Revisar en su pantalla" : "Abrir contexto"}</button></> : <><strong>Sin aviso seleccionado</strong><p>Elige una tarjeta para ver su contexto.</p></>}
        </aside>
      </div>

      <details className={styles.proof}>
        <summary>Recorrido Social Inbox · 26 pasos</summary>
        <ol>{["Abrir Inicio con tres avisos", "Ver badge 3", "Abrir Avisos", "Ver Pendientes", "Abrir asistencia pendiente", "Confirmar localmente en Partido", "Volver", "Contador baja a 2", "Abrir contrapropuesta de Reto", "Aceptar localmente en Retos", "Volver", "Contador baja a 1", "Abrir invitación de equipo", "Aceptar localmente en Equipo", "Contador desaparece", "Abrir Todos", "Ver plaza de Mercado aceptada", "Abrir Partido", "Marcar aviso informativo como leído", "Archivar actividad", "Marcar todos como leídos", "Abrir Ajustes", "Volver a Avisos", "Probar offline", "Probar cambio de usuario", "Reiniciar Demo"].map((step, index) => <li key={`${index}-${step}`}><b>{index + 1}</b>{step}</li>)}</ol>
        <footer><span>remoteWrites = 0</span><span>externalNotifications = 0</span><span>pushSent = 0</span><span>emailsSent = 0</span><span>realEntities = 0</span><span>StripeCalls = 0</span></footer>
      </details>
    </section>
  );
}
