"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "./supabaseClient";

type NotificationContext = {
  accessId?: string;
  accessStatus?: string;
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

type UserNotification = {
  actionUrl?: string;
  body: string;
  context: NotificationContext;
  createdAt: string;
  id: string;
  kind: string;
  readAt?: string;
  revision: number;
  serverSequence: number;
  title: string;
};

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
      context: row.context && typeof row.context === "object" ? row.context as NotificationContext : {},
      createdAt: typeof row.createdAt === "string" ? row.createdAt : "",
      id: row.id,
      kind: typeof row.kind === "string" ? row.kind : "general",
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
  const unreadCount = useMemo(() => notifications.filter((item) => !item.readAt).length, [notifications]);

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
            <button type="button" onClick={() => setOpen(false)} aria-label="Cerrar notificaciones">×</button>
          </header>
          {message ? <p className="notification-message" role="status">{message}</p> : null}
          <div className="notification-list">
            {notifications.map((notification) => {
              const invitationPending = notification.context.invitationStatus === "pending";
              const requestPending = notification.context.requestStatus === "pending"
                && Boolean(notification.context.requestGroupId);
              const reviewPending = notification.context.reviewStatus === "pending";
              return (
                <article className={notification.readAt ? "read" : "unread"} key={notification.id}>
                  <div>
                    <strong>{notification.title}</strong>
                    <p>{notification.body}</p>
                  </div>
                  <div className="notification-actions">
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
                    {notification.actionUrl ? <Link href={notification.actionUrl}>Ver partido</Link> : null}
                    {!notification.readAt ? (
                      <button className="text-action" type="button" disabled={busyId === notification.id} onClick={() => void markRead(notification)}>Marcar leída</button>
                    ) : null}
                  </div>
                </article>
              );
            })}
            {notifications.length === 0 ? <p className="notification-empty">No tienes avisos pendientes.</p> : null}
          </div>
        </section>
      ) : null}
    </aside>
  );
}
