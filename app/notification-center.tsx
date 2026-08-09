"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { conductClientMetadata } from "./conduct-contract";
import { supabase } from "./supabaseClient";

type NotificationContext = {
  accessId?: string;
  accessStatus?: string;
  attendanceId?: string;
  attendanceOutcome?: string;
  attendanceResponseState?: string;
  attendanceRevision?: number;
  groupRevision?: number;
  invitationId?: string;
  invitationRevision?: number;
  invitationStatus?: string;
  matchRevision?: number;
  requestGroupId?: string;
  requestGroupRevision?: number;
  requestId?: string;
  requestRevision?: number;
  requestStatus?: string;
  reviewId?: string;
  reviewRevision?: number;
  reviewStatus?: string;
};

type NotificationCategory = "achievement" | "challenge" | "group" | "market" | "match" | "security";

const notificationCategoryLabels: Record<NotificationCategory, string> = {
  achievement: "Logros",
  challenge: "Retos",
  group: "Grupo",
  market: "Mercado",
  match: "Partidos",
  security: "Seguridad",
};

type UserNotification = {
  actionUrl?: string;
  body: string;
  category: NotificationCategory;
  context: NotificationContext;
  createdAt: string;
  id: string;
  kind: string;
  mandatoryInApp: boolean;
  priority: "critical" | "high" | "normal";
  readAt?: string;
  revision: number;
  serverSequence: number;
  title: string;
};

function notificationCategory(value: unknown): NotificationCategory {
  return value === "achievement" || value === "challenge" || value === "market"
    || value === "match" || value === "security" ? value : "group";
}

function notificationMetadata() {
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-notifications" : "web-notifications",
  };
}

function normalizeNotifications(value: unknown): UserNotification[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const row = item as Record<string, unknown>;
    if (typeof row.id !== "string") return [];
    return [{
      actionUrl: typeof row.actionUrl === "string" ? row.actionUrl : undefined,
      body: typeof row.body === "string" ? row.body : "",
      category: notificationCategory(row.category),
      context: row.context && typeof row.context === "object" ? row.context as NotificationContext : {},
      createdAt: typeof row.createdAt === "string" ? row.createdAt : "",
      id: row.id,
      kind: typeof row.kind === "string" ? row.kind : "general",
      mandatoryInApp: Boolean(row.mandatoryInApp),
      priority: row.priority === "critical" || row.priority === "high" ? row.priority : "normal",
      readAt: typeof row.readAt === "string" ? row.readAt : undefined,
      revision: Math.max(1, Math.floor(Number(row.revision) || 1)),
      serverSequence: Math.max(0, Math.floor(Number(row.serverSequence) || 0)),
      title: typeof row.title === "string" ? row.title : "Aviso",
    }];
  });
}

export function NotificationCenter() {
  const [notifications, setNotifications] = useState<UserNotification[]>([]);
  const [open, setOpen] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<"all" | NotificationCategory>("all");
  const unreadCount = useMemo(() => notifications.filter((item) => !item.readAt).length, [notifications]);
  const visibleCategories = useMemo(() => (
    Object.keys(notificationCategoryLabels) as NotificationCategory[]
  ).filter((category) => notifications.some((item) => item.category === category)), [notifications]);
  const filteredNotifications = useMemo(() => selectedCategory === "all"
    ? notifications
    : notifications.filter((item) => item.category === selectedCategory), [notifications, selectedCategory]);

  async function loadNotifications() {
    if (!supabase) return;
    const session = await supabase.auth.getSession();
    const user = session.data.session?.user;
    setAuthenticated(Boolean(user));
    if (!user) {
      setNotifications([]);
      return;
    }
    const result = await supabase.rpc("get_pachanga_notification_center_v1");
    if (!result.error) setNotifications(normalizeNotifications(result.data));
  }

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let disposed = false;
    let channel: ReturnType<typeof client.channel> | null = null;
    let connectionGeneration = 0;

    const connect = async () => {
      const generation = ++connectionGeneration;
      const session = await client.auth.getSession();
      const user = session.data.session?.user;
      if (disposed || generation !== connectionGeneration) return;
      setAuthenticated(Boolean(user));
      if (channel) {
        await client.removeChannel(channel);
        channel = null;
      }
      if (!user) {
        setNotifications([]);
        return;
      }
      await loadNotifications();
      if (disposed || generation !== connectionGeneration) return;
      channel = client.channel(`notification-center-${user.id}`)
        .on("postgres_changes", {
          event: "*",
          schema: "public",
          table: "pachanga_user_notifications",
          filter: `recipient_user_id=eq.${user.id}`,
        }, () => void loadNotifications())
        .subscribe();
    };

    void connect();
    const { data: authSubscription } = client.auth.onAuthStateChange(() => {
      window.setTimeout(() => void connect(), 0);
    });
    return () => {
      disposed = true;
      connectionGeneration += 1;
      authSubscription.subscription.unsubscribe();
      if (channel) void client.removeChannel(channel);
    };
  }, []);

  async function markRead(notification: UserNotification) {
    if (!supabase || notification.readAt) return;
    setBusyId(notification.id);
    const result = await supabase.rpc("mark_pachanga_notification_read_v1", {
      expected_revision: notification.revision,
      operation_id: crypto.randomUUID(),
      target_notification_id: notification.id,
    });
    if (result.error) setMessage(result.error.message);
    await loadNotifications();
    setBusyId(null);
  }

  async function respondInvitation(notification: UserNotification, status: "accepted" | "rejected") {
    const context = notification.context;
    if (!supabase || !context.invitationId || !context.invitationRevision || context.matchRevision === undefined) return;
    setBusyId(notification.id);
    setMessage("");
    const result = await supabase.rpc("respond_pachanga_match_invitation_v1", {
      client_metadata: notificationMetadata(),
      expected_invitation_revision: context.invitationRevision,
      expected_match_revision: context.matchRevision,
      next_status: status,
      operation_id: crypto.randomUUID(),
      target_invitation_id: context.invitationId,
    });
    setMessage(result.error
      ? result.error.message
      : status === "accepted" ? "Invitación aceptada." : "Invitación rechazada.");
    await loadNotifications();
    setBusyId(null);
  }

  async function reviewWithdrawal(notification: UserNotification, status: "confirmed" | "dismissed") {
    const context = notification.context;
    if (!supabase || !context.reviewId || !context.reviewRevision || context.groupRevision === undefined) return;
    setBusyId(notification.id);
    setMessage("");
    const result = await supabase.rpc("review_pachanga_guest_withdrawal_v1", {
      client_metadata: notificationMetadata(),
      expected_group_revision: context.groupRevision,
      expected_review_revision: context.reviewRevision,
      next_status: status,
      operation_id: crypto.randomUUID(),
      target_review_id: context.reviewId,
    });
    setMessage(result.error
      ? result.error.message
      : status === "confirmed" ? "Abandono registrado como incidencia de conducta." : "Incidencia descartada.");
    await loadNotifications();
    setBusyId(null);
  }

  async function reviewOpenMatchRequest(notification: UserNotification, status: "accepted" | "rejected") {
    const context = notification.context;
    if (!supabase || !context.requestId || !context.requestGroupId || context.requestGroupRevision === undefined) return;
    setBusyId(notification.id);
    setMessage("");
    const result = await supabase.rpc("review_pachanga_open_match_request_authoritative_v2", {
      client_metadata: notificationMetadata(),
      expected_revision: context.requestGroupRevision,
      next_status: status,
      operation_id: crypto.randomUUID(),
      target_group_id: context.requestGroupId,
      target_request_id: context.requestId,
    });
    setMessage(result.error
      ? result.error.message
      : status === "accepted" ? "Solicitud aceptada." : "Solicitud rechazada.");
    await loadNotifications();
    setBusyId(null);
  }

  async function respondAttendance(notification: UserNotification, nextResponse: "agree" | "dispute") {
    const context = notification.context;
    if (!supabase || !context.attendanceId || !context.attendanceRevision) return;
    const responseNote = nextResponse === "dispute"
      ? window.prompt("Explica brevemente qué debe revisar el equipo.", "")?.trim()
      : "";
    if (nextResponse === "dispute" && !responseNote) return;
    setBusyId(notification.id);
    setMessage("");
    const result = await supabase.rpc("respond_pachanga_post_match_attendance_v1", {
      client_metadata: conductClientMetadata("notification-center"),
      expected_revision: context.attendanceRevision,
      next_response: nextResponse,
      operation_id: crypto.randomUUID(),
      response_note: responseNote ?? "",
      target_attendance_id: context.attendanceId,
    });
    setMessage(result.error ? result.error.message : "Respuesta de asistencia confirmada.");
    await loadNotifications();
    setBusyId(null);
  }

  if (!supabase || !authenticated) return null;

  return (
    <aside className={`notification-center ${open ? "open" : ""}`}>
      <button
        className="notification-trigger"
        type="button"
        aria-expanded={open}
        aria-controls="notification-panel"
        onClick={() => setOpen((value) => !value)}
      >
        <span>Avisos</span>
        {unreadCount ? <b>{unreadCount}</b> : null}
      </button>
      {open ? (
        <section className="notification-panel" id="notification-panel" aria-label="Centro de avisos">
          <header>
            <strong>Notificaciones</strong>
            <div>
              <Link href="/perfil/avisos">Configurar</Link>
              <button type="button" onClick={() => setOpen(false)} aria-label="Cerrar notificaciones">×</button>
            </div>
          </header>
          {message ? <p className="notification-message" role="status">{message}</p> : null}
          {visibleCategories.length ? (
            <div className="notification-filters" aria-label="Filtrar notificaciones">
              <button className={selectedCategory === "all" ? "active" : ""} type="button" onClick={() => setSelectedCategory("all")}>Todas</button>
              {visibleCategories.map((category) => (
                <button className={selectedCategory === category ? "active" : ""} type="button" key={category} onClick={() => setSelectedCategory(category)}>
                  {notificationCategoryLabels[category]}
                </button>
              ))}
            </div>
          ) : null}
          <div className="notification-list">
            {filteredNotifications.map((notification) => {
              const invitationPending = notification.context.invitationStatus === "pending";
              const attendancePending = notification.context.attendanceResponseState === "pending";
              const requestPending = notification.context.requestStatus === "pending"
                && Boolean(notification.context.requestGroupId);
              const reviewPending = notification.context.reviewStatus === "pending";
              return (
                <article className={notification.readAt ? "read" : "unread"} data-priority={notification.priority} key={notification.id}>
                  <div>
                    <span className="notification-category">
                      {notificationCategoryLabels[notification.category]}
                      {notification.mandatoryInApp ? <small>Obligatorio</small> : null}
                    </span>
                    <strong>{notification.title}</strong>
                    <p>{notification.body}</p>
                  </div>
                  <div className="notification-actions">
                    {attendancePending ? (
                      <>
                        <button type="button" disabled={busyId === notification.id} onClick={() => void respondAttendance(notification, "agree")}>De acuerdo</button>
                        <button className="secondary" type="button" disabled={busyId === notification.id} onClick={() => void respondAttendance(notification, "dispute")}>Revisar</button>
                      </>
                    ) : null}
                    {invitationPending ? (
                      <>
                        <button type="button" disabled={busyId === notification.id} onClick={() => void respondInvitation(notification, "accepted")}>Aceptar</button>
                        <button className="secondary" type="button" disabled={busyId === notification.id} onClick={() => void respondInvitation(notification, "rejected")}>Rechazar</button>
                      </>
                    ) : null}
                    {requestPending ? (
                      <>
                        <button type="button" disabled={busyId === notification.id} onClick={() => void reviewOpenMatchRequest(notification, "accepted")}>Aceptar plaza</button>
                        <button className="secondary" type="button" disabled={busyId === notification.id} onClick={() => void reviewOpenMatchRequest(notification, "rejected")}>Rechazar</button>
                      </>
                    ) : null}
                    {reviewPending ? (
                      <>
                        <button type="button" disabled={busyId === notification.id} onClick={() => void reviewWithdrawal(notification, "confirmed")}>Confirmar abandono</button>
                        <button className="secondary" type="button" disabled={busyId === notification.id} onClick={() => void reviewWithdrawal(notification, "dismissed")}>Descartar</button>
                      </>
                    ) : null}
                    {notification.actionUrl ? (
                      <Link
                        href={notification.actionUrl}
                        onClick={(event) => {
                          const target = new URL(notification.actionUrl!, window.location.origin);
                          if (
                            target.pathname === window.location.pathname
                            && target.searchParams.get("rewards") === "pending"
                          ) {
                            event.preventDefault();
                            window.history.pushState({}, "", target);
                            window.dispatchEvent(new Event("pachangas:reward-deep-link"));
                          }
                          setOpen(false);
                          void markRead(notification);
                        }}
                      >
                        {notification.category === "achievement" ? "Descubrir" : notification.category === "challenge" ? "Ver reto" : "Abrir"}
                      </Link>
                    ) : null}
                    {!notification.readAt ? (
                      <button className="text-action" type="button" disabled={busyId === notification.id} onClick={() => void markRead(notification)}>Marcar leída</button>
                    ) : null}
                  </div>
                </article>
              );
            })}
            {filteredNotifications.length === 0 ? <p className="notification-empty">No hay avisos en esta categoría.</p> : null}
          </div>
        </section>
      ) : null}
    </aside>
  );
}
