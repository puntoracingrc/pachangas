"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { ProductFeedback, ProductState } from "../_components/product-state";
import {
  SOCIAL_INBOX_DOMAINS,
  socialInboxGroup,
  type SocialInboxGroup,
  type SocialInboxItem,
} from "../social-inbox-contract";
import { useSocialInbox } from "../social-inbox-provider";
import styles from "./social-inbox.module.css";

const groupLabels: Record<SocialInboxGroup, string> = {
  attention: "Necesita tu atención",
  older: "Anteriores",
  today: "Hoy",
  week: "Esta semana",
};

const groupOrder: SocialInboxGroup[] = ["attention", "today", "week", "older"];

function relativeDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Fecha no disponible";
  const elapsed = Date.now() - date.getTime();
  const minutes = Math.floor(elapsed / 60000);
  if (minutes >= 0 && minutes < 1) return "Ahora";
  if (minutes >= 0 && minutes < 60) return `Hace ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours >= 0 && hours < 24) return `Hace ${hours} h`;
  return new Intl.DateTimeFormat("es-ES", { day: "2-digit", month: "short", year: date.getFullYear() === new Date().getFullYear() ? undefined : "numeric" }).format(date);
}

function domainMark(domain: SocialInboxItem["sourceDomain"]) {
  if (domain === "MATCH") return "P";
  if (domain === "CHALLENGE") return "R";
  if (domain === "MARKET") return "M";
  return "E";
}

function NotificationMenu({ item }: { item: SocialInboxItem }) {
  const { busyId, offline, runCommand } = useSocialInbox();
  const busy = busyId === item.id;
  return (
    <details className={styles.itemMenu}>
      <summary aria-label={`Más acciones para ${item.title}`}>•••</summary>
      <div role="menu">
        <button disabled={busy || offline} role="menuitem" type="button" onClick={() => void runCommand(item.readState === "READ" ? "inbox.mark_unread" : "inbox.mark_read", item)}>
          {item.readState === "READ" ? "Marcar como no leído" : "Marcar como leído"}
        </button>
        <button disabled={busy || offline} role="menuitem" type="button" onClick={() => void runCommand("inbox.archive", item)}>Archivar</button>
      </div>
    </details>
  );
}
function InboxCard({ item, onSelect, selected }: { item: SocialInboxItem; onSelect: () => void; selected: boolean }) {
  return (
    <article
      className={styles.card}
      data-attention={item.attentionState}
      data-read={item.readState}
      data-selected={selected || undefined}
    >
      <span className={styles.domainMark} data-domain={item.sourceDomain} aria-hidden="true">{domainMark(item.sourceDomain)}</span>
      <button className={styles.cardCopy} type="button" onClick={onSelect} aria-label={`Ver detalle de ${item.title}`}>
        <span className={styles.cardMeta}>{item.context} · {relativeDate(item.occurredAt)}</span>
        <strong>{item.title}</strong>
        <p>{item.summary}</p>
        <small>{item.statusLabel}</small>
      </button>
      <div className={styles.cardActions}>
        {item.deepLink ? <Link href={item.deepLink}>{item.ctaLabel}</Link> : null}
        <NotificationMenu item={item} />
      </div>
    </article>
  );
}

function InboxDetail({ item }: { item: SocialInboxItem | null }) {
  if (!item) return <aside className={styles.detail}><span>Selecciona un aviso</span><h2>Tu siguiente acción aparecerá aquí</h2><p>La bandeja solo enlaza a la pantalla que conserva la autoridad del partido, reto, mercado o equipo.</p></aside>;
  return (
    <aside className={styles.detail} data-attention={item.attentionState}>
      <span>{item.context}</span>
      <h2>{item.title}</h2>
      <p>{item.summary}</p>
      <dl><div><dt>Estado</dt><dd>{item.statusLabel}</dd></div><div><dt>Cuándo</dt><dd>{relativeDate(item.occurredAt)}</dd></div></dl>
      {item.deepLink ? <Link className={styles.primaryAction} href={item.deepLink}>{item.ctaLabel}</Link> : <small>Esta actividad ya no tiene una acción disponible.</small>}
      <NotificationMenu item={item} />
    </aside>
  );
}

export default function SocialInboxPage() {
  const {
    busyId,
    domain,
    error,
    loadMore,
    offline,
    refresh,
    runCommand,
    setDomain,
    setView,
    snapshot,
    status,
    view,
  } = useSocialInbox();
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    setView("pending");
    setDomain(null);
  }, [setDomain, setView]);

  const groups = useMemo(() => groupOrder.map((group) => ({
    group,
    items: (snapshot?.items ?? []).filter((item) => socialInboxGroup(item) === group),
  })).filter((entry) => entry.items.length > 0), [snapshot?.items]);
  const selected = snapshot?.items.find((item) => item.id === selectedId) ?? snapshot?.items[0] ?? null;
  const signedOut = status === "signed-out";
  const unavailable = status === "unavailable";

  return (
    <OfficialProductShellV2
      active="perfil"
      context={{ detail: "Partidos, Retos, Mercado y Equipo", eyebrow: "Actividad social", title: "Avisos", type: "profile" }}
    >
      <main className={styles.page} data-inbox-offline={offline || undefined}>
        <header className={styles.header}>
          <div><span>Actividad social</span><h1>Avisos</h1><p>Lo que necesita tu atención y la actividad reciente de tus equipos.</p></div>
          <div className={styles.headerActions}>
            <Link href="/ajustes/notificaciones">Ajustes</Link>
            <button disabled={offline || busyId === "all" || !snapshot?.unreadCount} type="button" onClick={() => void runCommand("inbox.mark_all_read")}>Marcar todo leído</button>
          </div>
        </header>

        <div className={styles.toolbar}>
          <div className={styles.views} role="tablist" aria-label="Vista de avisos">
            <button aria-selected={view === "pending"} role="tab" type="button" onClick={() => setView("pending")}>Pendientes{snapshot?.pendingCount ? ` · ${snapshot.pendingCount}` : ""}</button>
            <button aria-selected={view === "all"} role="tab" type="button" onClick={() => setView("all")}>Todos</button>
          </div>
          <details className={styles.filters}>
            <summary>Filtrar{domain ? ` · ${SOCIAL_INBOX_DOMAINS.find((entry) => entry.id === domain)?.label}` : ""}</summary>
            <div>
              <button aria-pressed={domain === null} type="button" onClick={() => setDomain(null)}>Todo</button>
              {SOCIAL_INBOX_DOMAINS.map((entry) => <button aria-pressed={domain === entry.id} key={entry.id} type="button" onClick={() => setDomain(entry.id)}>{entry.label}</button>)}
            </div>
          </details>
        </div>

        {offline && snapshot ? <p className={styles.offlineNotice} role="status">Resultados guardados · última actualización {relativeDate(snapshot.fetchedAt)}. Necesitas conexión para confirmar cambios.</p> : null}
        {error ? <ProductFeedback tone="error">{error}</ProductFeedback> : null}

        {signedOut ? <ProductState actions={<Link href="/">Ir a Inicio</Link>} description="Entra con tu cuenta para consultar la actividad social dirigida a ti." eyebrow="Sesión necesaria" title="Tus avisos son privados" />
          : unavailable ? <ProductState description="La conexión con Pachangas IQ no está configurada en este entorno." eyebrow="Servicio no disponible" title="No podemos abrir tus avisos" />
            : status === "loading" && !snapshot ? <section className={styles.loading} aria-busy="true" aria-label="Cargando avisos"><i /><i /><i /></section>
              : status === "error" && !snapshot ? <ProductState actions={<button type="button" onClick={() => void refresh()}>Reintentar</button>} description={error || "No pudimos recuperar una copia segura de tus avisos."} eyebrow="No se pudo cargar" state="ERROR" title="Avisos no disponibles" />
                : snapshot && !snapshot.items.length ? <ProductState actions={view === "pending" ? <button type="button" onClick={() => setView("all")}>Ver actividad reciente</button> : undefined} description={view === "pending" ? "No tienes ninguna respuesta pendiente en Partidos, Retos, Mercado o Equipo." : "La actividad social reciente aparecerá aquí cuando ocurra."} eyebrow={view === "pending" ? "Todo al día" : "Sin actividad"} state="SUCCESS" title={view === "pending" ? "No queda nada pendiente" : "Tu bandeja está vacía"} />
                  : snapshot ? <div className={styles.inboxLayout}>
                    <section className={styles.list} aria-label="Lista de avisos">
                      {groups.map(({ group, items }) => <section className={styles.group} key={group}><h2>{groupLabels[group]}</h2>{items.map((item) => <InboxCard item={item} key={item.id} onSelect={() => setSelectedId(item.id)} selected={selected?.id === item.id} />)}</section>)}
                      {snapshot.hasMore ? <button className={styles.loadMore} disabled={Boolean(busyId)} type="button" onClick={() => void loadMore()}>Ver anteriores</button> : null}
                    </section>
                    <InboxDetail item={selected} />
                  </div> : null}
        <p className={styles.liveStatus} aria-live="polite">{busyId ? "Confirmando el cambio con el servidor." : status === "ready" ? "Bandeja actualizada." : ""}</p>
      </main>
    </OfficialProductShellV2>
  );
}
