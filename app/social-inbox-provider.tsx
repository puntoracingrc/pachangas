"use client";

import { usePathname } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { clearSocialInboxCache, readSocialInboxCache, writeSocialInboxCache } from "./social-inbox-cache";
import {
  normalizeSocialInboxSnapshot,
  socialInboxError,
  type SocialInboxDomain,
  type SocialInboxItem,
  type SocialInboxSnapshot,
  type SocialInboxView,
} from "./social-inbox-contract";
import { supabase } from "./supabaseClient";

type SocialInboxStatus = "error" | "idle" | "loading" | "offline" | "ready" | "signed-out" | "unavailable";
type InboxCommand = "inbox.archive" | "inbox.mark_all_read" | "inbox.mark_read" | "inbox.mark_unread";

type SocialInboxContextValue = {
  busyId: string | null;
  domain: SocialInboxDomain | null;
  error: string;
  loadMore: () => Promise<void>;
  offline: boolean;
  pendingSnapshot: SocialInboxSnapshot | null;
  refresh: () => Promise<void>;
  runCommand: (command: InboxCommand, item?: SocialInboxItem) => Promise<boolean>;
  setDomain: (domain: SocialInboxDomain | null) => void;
  setView: (view: SocialInboxView) => void;
  snapshot: SocialInboxSnapshot | null;
  status: SocialInboxStatus;
  userId: string | null;
  view: SocialInboxView;
};

const SocialInboxContext = createContext<SocialInboxContextValue | null>(null);

function shouldConnect(pathname: string) {
  return !pathname.startsWith("/demo")
    && !pathname.startsWith("/admin")
    && !pathname.startsWith("/laboratorio");
}

function mergeSnapshots(current: SocialInboxSnapshot | null, next: SocialInboxSnapshot) {
  if (!current || current.view !== next.view || current.domain !== next.domain) return next;
  const seen = new Set(current.items.map((item) => item.id));
  return { ...next, items: [...current.items, ...next.items.filter((item) => !seen.has(item.id))] };
}

export function SocialInboxProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const enabled = shouldConnect(pathname);
  const [userId, setUserId] = useState<string | null>(null);
  const [snapshot, setSnapshot] = useState<SocialInboxSnapshot | null>(null);
  const [pendingSnapshot, setPendingSnapshot] = useState<SocialInboxSnapshot | null>(null);
  const [status, setStatus] = useState<SocialInboxStatus>("idle");
  const [error, setError] = useState("");
  const [offline, setOffline] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [view, setView] = useState<SocialInboxView>("pending");
  const [domain, setDomain] = useState<SocialInboxDomain | null>(null);
  const userRef = useRef<string | null>(null);
  const snapshotRef = useRef<SocialInboxSnapshot | null>(null);
  const viewRef = useRef<SocialInboxView>("pending");
  const domainRef = useRef<SocialInboxDomain | null>(null);
  const requestGeneration = useRef(0);
  const invalidationTimer = useRef<number | null>(null);
  const commandInFlightActor = useRef<string | null>(null);

  useEffect(() => { viewRef.current = view; }, [view]);
  useEffect(() => { domainRef.current = domain; }, [domain]);
  useEffect(() => { snapshotRef.current = snapshot; }, [snapshot]);

  const fetchInbox = useCallback(async ({ append = false, pendingCache = false }: { append?: boolean; pendingCache?: boolean } = {}) => {
    const actorId = userRef.current;
    if (!enabled || !actorId || !supabase) return;
    const requestId = ++requestGeneration.current;
    const selectedView = pendingCache ? "pending" : viewRef.current;
    const selectedDomain = pendingCache ? null : domainRef.current;
    const cursor = append && !pendingCache ? snapshotRef.current?.nextCursor : null;
    if (!append && !snapshotRef.current) setStatus("loading");
    const result = await supabase.rpc("get_my_pachanga_social_inbox_v1", {
      cursor_notification_id: cursor?.notificationId ?? null,
      cursor_server_sequence: cursor?.serverSequence ?? null,
      cursor_sort_rank: cursor?.sortRank ?? null,
      page_size: 25,
      target_domain: selectedDomain,
      target_view: selectedView,
    });
    if (requestId !== requestGeneration.current || actorId !== userRef.current) return;
    if (result.error) {
      setError(socialInboxError(result.error, "No pudimos recuperar tus avisos."));
      setStatus(snapshotRef.current ? "offline" : "error");
      return;
    }
    const normalized = normalizeSocialInboxSnapshot(result.data);
    if (!normalized) {
      setError("El servidor no devolvió una bandeja válida.");
      setStatus(snapshotRef.current ? "offline" : "error");
      return;
    }
    setError("");
    setOffline(false);
    setStatus("ready");
    if (pendingCache) {
      setPendingSnapshot(normalized);
      await writeSocialInboxCache(actorId, normalized);
      if (viewRef.current === "pending" && domainRef.current === null) setSnapshot(normalized);
      else setSnapshot((current) => current ? { ...current, pendingCount: normalized.pendingCount, unreadCount: normalized.unreadCount, serverSequence: normalized.serverSequence } : current);
      return;
    }
    setSnapshot((current) => append ? mergeSnapshots(current, normalized) : normalized);
    if (normalized.view === "pending" && normalized.domain === null) {
      setPendingSnapshot(normalized);
      await writeSocialInboxCache(actorId, normalized);
    }
  }, [enabled]);

  const refresh = useCallback(async () => {
    await fetchInbox();
    if (viewRef.current !== "pending" || domainRef.current !== null) await fetchInbox({ pendingCache: true });
  }, [fetchInbox]);

  const scheduleRefresh = useCallback(() => {
    if (invalidationTimer.current !== null) window.clearTimeout(invalidationTimer.current);
    invalidationTimer.current = window.setTimeout(() => {
      invalidationTimer.current = null;
      void refresh();
    }, 160);
  }, [refresh]);

  useEffect(() => {
    if (!enabled || !supabase) {
      let cancelled = false;
      userRef.current = null;
      commandInFlightActor.current = null;
      window.queueMicrotask(() => {
        if (cancelled) return;
        setUserId(null);
        setSnapshot(null);
        setPendingSnapshot(null);
        setBusyId(null);
        setStatus(supabase ? "idle" : "unavailable");
      });
      return () => { cancelled = true; };
    }
    const client = supabase;
    let disposed = false;
    let channel: ReturnType<typeof client.channel> | null = null;
    let sessionGeneration = 0;

    const connect = async () => {
      const generation = ++sessionGeneration;
      const sessionResult = await client.auth.getSession();
      if (disposed || generation !== sessionGeneration) return;
      const nextUserId = sessionResult.data.session?.user.id ?? null;
      const previousChannel = channel;
      channel = null;
      if (previousChannel) await client.removeChannel(previousChannel);
      if (disposed || generation !== sessionGeneration) return;
      requestGeneration.current += 1;
      const previousUserId = userRef.current;
      userRef.current = nextUserId;
      commandInFlightActor.current = null;
      setUserId(nextUserId);
      setBusyId(null);
      setError("");
      if (!nextUserId) {
        setSnapshot(null);
        setPendingSnapshot(null);
        setStatus("signed-out");
        if (previousUserId) await clearSocialInboxCache();
        return;
      }
      setSnapshot(null);
      setPendingSnapshot(null);
      setStatus("loading");
      const cached = await readSocialInboxCache(nextUserId);
      if (disposed || generation !== sessionGeneration || userRef.current !== nextUserId) return;
      if (cached) {
        setSnapshot(cached.snapshot);
        setPendingSnapshot(cached.snapshot);
        setStatus(navigator.onLine ? "loading" : "offline");
      }
      setOffline(!navigator.onLine);
      if (navigator.onLine) await fetchInbox({ pendingCache: true });
      if (disposed || generation !== sessionGeneration || userRef.current !== nextUserId) return;
      channel = client.channel(`social-inbox-v1-${nextUserId}`)
        .on("postgres_changes", {
          event: "*",
          filter: `recipient_user_id=eq.${nextUserId}`,
          schema: "public",
          table: "pachanga_user_notifications",
        }, scheduleRefresh)
        .subscribe((nextStatus) => {
          if (nextStatus === "SUBSCRIBED") scheduleRefresh();
          if (nextStatus === "CHANNEL_ERROR" || nextStatus === "TIMED_OUT") setStatus((current) => current === "ready" ? "offline" : current);
        });
    };

    void connect();
    const { data: authSubscription } = client.auth.onAuthStateChange(() => {
      window.setTimeout(() => void connect(), 0);
    });
    const onlineHandler = () => {
      setOffline(false);
      scheduleRefresh();
    };
    const offlineHandler = () => {
      setOffline(true);
      setStatus((current) => snapshotRef.current ? "offline" : current);
    };
    const visibilityHandler = () => {
      if (document.visibilityState === "visible" && navigator.onLine) scheduleRefresh();
    };
    window.addEventListener("online", onlineHandler);
    window.addEventListener("offline", offlineHandler);
    window.addEventListener("pachangas:rewards-updated", scheduleRefresh);
    document.addEventListener("visibilitychange", visibilityHandler);
    return () => {
      disposed = true;
      sessionGeneration += 1;
      requestGeneration.current += 1;
      authSubscription.subscription.unsubscribe();
      window.removeEventListener("online", onlineHandler);
      window.removeEventListener("offline", offlineHandler);
      window.removeEventListener("pachangas:rewards-updated", scheduleRefresh);
      document.removeEventListener("visibilitychange", visibilityHandler);
      if (invalidationTimer.current !== null) window.clearTimeout(invalidationTimer.current);
      if (channel) void client.removeChannel(channel);
    };
  }, [enabled, fetchInbox, scheduleRefresh]);

  useEffect(() => {
    if (!userRef.current || !enabled) return;
    void fetchInbox();
  }, [domain, enabled, fetchInbox, pathname, view]);

  const loadMore = useCallback(async () => {
    if (!snapshot?.hasMore || busyId) return;
    await fetchInbox({ append: true });
  }, [busyId, fetchInbox, snapshot?.hasMore]);

  const runCommand = useCallback(async (command: InboxCommand, item?: SocialInboxItem) => {
    const actorId = userRef.current;
    if (!supabase || !actorId) {
      setError("Inicia sesión para actualizar tus avisos.");
      return false;
    }
    if (commandInFlightActor.current) return false;
    if (!navigator.onLine) {
      setOffline(true);
      setError("Necesitas conexión para confirmar esta acción.");
      return false;
    }
    const target = command === "inbox.mark_all_read" ? "all" : item?.id ?? null;
    if (command !== "inbox.mark_all_read" && !item) return false;
    commandInFlightActor.current = actorId;
    setBusyId(target);
    setError("");
    try {
      const result = await supabase.rpc("command_pachanga_social_inbox_v1", {
        action: command,
        expected_revision: item?.revision ?? null,
        expected_server_sequence: command === "inbox.mark_all_read" ? snapshotRef.current?.serverSequence ?? 0 : null,
        operation_id: crypto.randomUUID(),
        target_notification_id: item?.id ?? null,
      });
      if (actorId !== userRef.current) return false;
      if (result.error) {
        const message = socialInboxError(result.error);
        setError(message);
        if (message.includes("ha cambiado")) await refresh();
        return false;
      }
      await refresh();
      return actorId === userRef.current;
    } catch (caught) {
      if (actorId === userRef.current) setError(socialInboxError(caught));
      return false;
    } finally {
      if (commandInFlightActor.current === actorId) commandInFlightActor.current = null;
      if (actorId === userRef.current) setBusyId(null);
    }
  }, [refresh]);

  const value = useMemo<SocialInboxContextValue>(() => ({
    busyId,
    domain,
    error,
    loadMore,
    offline,
    pendingSnapshot,
    refresh,
    runCommand,
    setDomain,
    setView,
    snapshot,
    status,
    userId,
    view,
  }), [busyId, domain, error, loadMore, offline, pendingSnapshot, refresh, runCommand, snapshot, status, userId, view]);

  return <SocialInboxContext.Provider value={value}>{children}</SocialInboxContext.Provider>;
}

export function useSocialInbox() {
  const value = useContext(SocialInboxContext);
  if (!value) throw new Error("useSocialInbox must be used within SocialInboxProvider");
  return value;
}
