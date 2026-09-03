"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { MobileAppNav, type AdminViewPreviewControl, type MobileAppTab } from "../mobile-app-nav";
import { supabase } from "../supabaseClient";
import type { ProductContextOption } from "./product-context-selector";
import {
  PRODUCT_PRIMARY_DESTINATIONS,
  type ProductActorPerspective,
} from "./product-navigation-contract";
import { useCanonicalPlatformOwner } from "./use-canonical-platform-owner";
import { useSocialInbox } from "../social-inbox-provider";
import {
  OFFICIAL_UI_V2_VERSION,
  resolveOfficialLayoutMode,
  type OfficialLayoutMode,
  type OfficialShellVariant,
} from "../_design-v2/official-ui-v2-contract";
import styles from "./official-product-shell-v2.module.css";

type OfficialContext = {
  detail?: string;
  eyebrow?: string;
  id?: string;
  nextAction?: string;
  role?: string;
  status?: string;
  title: string;
  type?: ProductContextOption["type"];
};

type ShellLinkMap = Partial<Record<MobileAppTab, string>>;

type ShellAccount = {
  avatarUrl?: string;
  cardHref?: string;
  displayName?: string;
  notificationsHref?: string;
  onSignOut?: () => void | Promise<void>;
  profileHref?: string;
  settingsHref?: string;
  teamHref?: string;
};

type OfficialProductShellV2Props = {
  account?: ShellAccount;
  active: MobileAppTab;
  adminViewPreview?: AdminViewPreviewControl;
  children: ReactNode;
  context: OfficialContext;
  contextVisual?: ReactNode;
  contextOptions?: ProductContextOption[];
  links?: ShellLinkMap;
  navigationEnabled?: boolean;
  onContextChange?: (id: string) => void;
  onNavigate?: (tab: MobileAppTab) => void;
  perspective?: ProductActorPerspective;
  variant?: OfficialShellVariant;
};

const primaryItems: Array<{ id: MobileAppTab; label: string; short: string }> = PRODUCT_PRIMARY_DESTINATIONS;

const defaultLinks: ShellLinkMap = {
  competir: "/competiciones",
  equipo: "/equipo",
  inicio: "/?mobile=inicio",
  mercado: "/mercado",
  partido: "/?mobile=partido",
  perfil: "/?mobile=perfil",
  retos: "/retos",
};

function currentViewport(): OfficialLayoutMode {
  if (typeof window === "undefined") return "DESKTOP";
  const coarsePointer = window.matchMedia("(pointer: coarse)").matches
    || window.matchMedia("(any-pointer: coarse)").matches;
  const width = Math.round(window.visualViewport?.width ?? window.innerWidth);
  const height = Math.round(window.visualViewport?.height ?? window.innerHeight);
  return resolveOfficialLayoutMode({
    coarsePointer,
    height,
    landscape: window.matchMedia("(orientation: landscape)").matches,
    width,
  });
}

function useOfficialLayoutMode() {
  const [mode, setMode] = useState<OfficialLayoutMode>("DESKTOP");

  useEffect(() => {
    const update = () => setMode(currentViewport());
    const viewport = window.visualViewport;
    update();
    window.addEventListener("resize", update);
    window.addEventListener("orientationchange", update);
    viewport?.addEventListener("resize", update);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("orientationchange", update);
      viewport?.removeEventListener("resize", update);
    };
  }, []);

  return mode;
}

function ShellDestination({
  active,
  href,
  id,
  label,
  onNavigate,
  short,
}: {
  active: boolean;
  href?: string;
  id: MobileAppTab;
  label: string;
  onNavigate?: (tab: MobileAppTab) => void;
  short: string;
}) {
  const content = <><b aria-hidden="true">{short}</b><span>{label}</span></>;
  if (href) {
    return <Link href={href} aria-current={active ? "page" : undefined}>{content}</Link>;
  }
  return (
    <button type="button" aria-current={active ? "page" : undefined} onClick={() => onNavigate?.(id)}>
      {content}
    </button>
  );
}

function BellIcon() {
  return <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M6 9a6 6 0 0 1 12 0v5l2 3H4l2-3zM10 20h4" /></svg>;
}

function UserIcon() {
  return <svg aria-hidden="true" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" /><path d="M4.5 21c.4-5.2 2.9-8 7.5-8s7.1 2.8 7.5 8" /></svg>;
}

function ContextIdentity({
  context,
  contexts,
  onContextChange,
  perspective,
  visual,
}: {
  context: OfficialContext;
  contexts: ProductContextOption[];
  onContextChange?: (id: string) => void;
  perspective: ProductActorPerspective;
  visual?: ReactNode;
}) {
  const activeId = context.id ?? contexts[0]?.id ?? "current";
  const canManageTeam = perspective === "team-admin" || perspective === "team-owner";
  const isPlayerWithoutTeam = context.type === "profile";

  return (
    <details className={styles.identityMenu}>
      <summary aria-label="Abrir selector de equipo">
        <span className={styles.identityVisual}>{visual ?? <Image src="/icon-192.png" alt="" width={38} height={38} priority unoptimized />}</span>
        <span><small>{isPlayerWithoutTeam ? "Tu espacio" : "Equipo activo"}</small><strong>{context.title}</strong></span>
        <b aria-hidden="true">⌄</b>
      </summary>
      <div className={styles.identityMenuPanel}>
        {contexts.length > 1 && onContextChange ? (
          <label>
            <span>Cambiar equipo</span>
            <select value={activeId} onChange={(event) => onContextChange(event.target.value)}>
              {contexts.map((entry) => <option key={entry.id} value={entry.id}>{entry.title}</option>)}
            </select>
          </label>
        ) : <p>{context.detail ?? context.role ?? "Tu espacio de juego"}</p>}
        {!isPlayerWithoutTeam ? <Link href="/equipo">Ver equipo</Link> : <Link href="/equipo/unirse">Unirme a un equipo</Link>}
        {!isPlayerWithoutTeam && canManageTeam ? <Link href="/?mobile=perfil&settings=1">Gestionar equipo</Link> : null}
        <Link href="/equipo/crear">Crear equipo</Link>
        {isPlayerWithoutTeam ? <Link href="/mercado?tab=partidos">Buscar una pachanga</Link> : null}
      </div>
    </details>
  );
}

function AccountActions({
  account,
  adminViewPreview,
  isPlayerWithoutTeam,
  platformOwner,
}: {
  account: ShellAccount;
  adminViewPreview?: AdminViewPreviewControl;
  isPlayerWithoutTeam: boolean;
  platformOwner: boolean;
}) {
  const notificationsHref = account.notificationsHref ?? "/avisos";
  const { pendingSnapshot, snapshot, status } = useSocialInbox();
  const summary = pendingSnapshot ?? snapshot;
  const pendingCount = summary?.pendingCount ?? 0;
  const unreadCount = summary?.unreadCount ?? 0;
  const bellLabel = pendingCount > 0
    ? `Avisos, ${pendingCount} ${pendingCount === 1 ? "acción pendiente" : "acciones pendientes"}`
    : unreadCount > 0
      ? `Avisos, ${unreadCount} ${unreadCount === 1 ? "aviso nuevo" : "avisos nuevos"}`
      : "Avisos";

  async function signOut() {
    if (account.onSignOut) await account.onSignOut();
    else await supabase?.auth.signOut();
    try {
      await fetch("/api/platform-admin/session", {
        method: "DELETE",
        headers: { "X-Pachangas-Platform-Admin": "1" },
      });
    } finally {
      if (!account.onSignOut) window.location.assign("/");
    }
  }

  return (
    <div className={styles.accountActions}>
      <Link className={styles.iconAction} data-inbox-status={status} href={notificationsHref} aria-label={bellLabel}>
        <BellIcon />
        {pendingCount > 0 ? <span className={styles.notificationBadge} aria-hidden="true">{pendingCount > 9 ? "9+" : pendingCount}</span>
          : unreadCount > 0 ? <span className={styles.notificationDot} aria-hidden="true" /> : null}
      </Link>
      <details className={styles.accountMenu}>
        <summary className={styles.avatarAction} aria-label="Abrir menú de cuenta">
          {account.avatarUrl ? <Image src={account.avatarUrl} alt="" width={34} height={34} unoptimized /> : <UserIcon />}
        </summary>
        <div className={styles.accountMenuPanel}>
          <p><strong>{account.displayName ?? "Mi cuenta"}</strong><small>Vista jugador</small></p>
          <Link href={account.profileHref ?? "/perfil"}>Mi perfil</Link>
          <Link href={account.cardHref ?? "/personalizar-carta"}>Mi carta</Link>
          <Link href={isPlayerWithoutTeam ? "/?social=start" : account.teamHref ?? "/equipo"}>{isPlayerWithoutTeam ? "Empezar" : "Mi equipo"}</Link>
          <Link href={account.settingsHref ?? "/?mobile=perfil&settings=1"}>Ajustes</Link>
          {adminViewPreview ? (
            <button type="button" onClick={adminViewPreview.onToggle}>
              {adminViewPreview.active ? "Volver a vista admin" : "Ver como jugador"}
            </button>
          ) : null}
          {platformOwner ? <hr /> : null}
          {platformOwner ? <Link href="/admin">Administración</Link> : null}
          {platformOwner ? <Link href="/admin/demo">Mundo Demo completo</Link> : null}
          <button className={styles.signOut} type="button" onClick={() => void signOut()}>Cerrar sesión</button>
        </div>
      </details>
    </div>
  );
}

export function OfficialProductShellV2({
  account = {},
  active,
  adminViewPreview,
  children,
  context,
  contextVisual,
  contextOptions,
  links,
  navigationEnabled = true,
  onContextChange,
  onNavigate,
  perspective = "player",
  variant = "PRODUCT",
}: OfficialProductShellV2Props) {
  const mode = useOfficialLayoutMode();
  const platformOwner = useCanonicalPlatformOwner();

  useEffect(() => {
    document.body.classList.add("official-product-active");
    return () => document.body.classList.remove("official-product-active");
  }, []);
  const destinations = { ...defaultLinks, ...links };
  const resolvedContexts: ProductContextOption[] = contextOptions?.length ? contextOptions : [{
    detail: context.detail,
    id: context.id ?? "current",
    nextAction: context.nextAction,
    role: context.role ?? perspective,
    status: context.status,
    title: context.title,
    type: context.type ?? (perspective.includes("organizer") ? "competition" : perspective.startsWith("platform") ? "platform" : "team"),
  }];
  const destinationFor = (id: MobileAppTab) => onNavigate && links?.[id] === undefined ? undefined : destinations[id];

  const identity = (
    <ContextIdentity
      context={context}
      contexts={resolvedContexts}
      onContextChange={onContextChange}
      perspective={perspective}
      visual={contextVisual}
    />
  );
  const accountActions = <AccountActions account={account} adminViewPreview={adminViewPreview} isPlayerWithoutTeam={context.type === "profile"} platformOwner={platformOwner} />;

  return (
    <div
      className={styles.shell}
      data-layout-mode={mode}
      data-navigation-enabled={navigationEnabled ? "true" : "false"}
      data-official-ui-version={OFFICIAL_UI_V2_VERSION}
      data-shell-variant={variant}
      data-social-core="v3a"
    >
      <header className={styles.desktopHeader}>
        {identity}
        {navigationEnabled ? <nav className={styles.desktopNav} aria-label="Navegación principal">
          {primaryItems.map((item) => (
            <ShellDestination
              active={active === item.id}
              href={destinationFor(item.id)}
              id={item.id}
              key={item.id}
              label={item.label}
              onNavigate={onNavigate}
              short={item.short}
            />
          ))}
        </nav> : <span />}
        {navigationEnabled ? accountActions : <span />}
      </header>

      <div className={styles.gameFrame}>
        {navigationEnabled ? <aside className={styles.gameRail} aria-label="Navegación de modo juego">
          <Link className={styles.gameMark} href="/" aria-label="Pachangas IQ, Inicio">IQ</Link>
          <nav>
            {primaryItems.map((item) => (
              <ShellDestination
                active={active === item.id}
                href={destinationFor(item.id)}
                id={item.id}
                key={item.id}
                label={item.label}
                onNavigate={onNavigate}
                short={item.short}
              />
            ))}
          </nav>
        </aside> : null}

        <div className={styles.viewport}>
          <header className={styles.contextBar}>
            {identity}
            {navigationEnabled ? accountActions : null}
          </header>
          <div className={styles.content}>{children}</div>
        </div>
      </div>

      {navigationEnabled ? <div className={styles.portraitNav}>
        <MobileAppNav
          active={active}
          links={onNavigate ? links : destinations}
          onNavigate={onNavigate}
        />
      </div> : null}
    </div>
  );
}
