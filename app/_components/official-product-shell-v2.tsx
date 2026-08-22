"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState, type ReactNode } from "react";
import { MobileAppNav, type AdminViewPreviewControl, type MobileAppTab } from "../mobile-app-nav";
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
  status?: string;
  title: string;
};

type ShellLinkMap = Partial<Record<MobileAppTab, string>>;

type OfficialProductShellV2Props = {
  active: MobileAppTab;
  adminViewPreview?: AdminViewPreviewControl;
  children: ReactNode;
  context: OfficialContext;
  links?: ShellLinkMap;
  navigationEnabled?: boolean;
  onNavigate?: (tab: MobileAppTab) => void;
  variant?: OfficialShellVariant;
};

const primaryItems: Array<{ id: MobileAppTab; label: string; short: string }> = [
  { id: "inicio", label: "Inicio", short: "IN" },
  { id: "partido", label: "Partido", short: "PA" },
  { id: "mercado", label: "Mercado", short: "ME" },
  { id: "equipo", label: "Equipo", short: "EQ" },
  { id: "perfil", label: "Perfil", short: "PF" },
];

const defaultLinks: ShellLinkMap = {
  equipo: "/?mobile=equipo",
  inicio: "/?mobile=inicio",
  mercado: "/mercado",
  partido: "/?mobile=partido",
  perfil: "/?mobile=perfil",
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

export function OfficialProductShellV2({
  active,
  adminViewPreview,
  children,
  context,
  links,
  navigationEnabled = true,
  onNavigate,
  variant = "PRODUCT",
}: OfficialProductShellV2Props) {
  const mode = useOfficialLayoutMode();
  const destinations = { ...defaultLinks, ...links };
  const destinationFor = (id: MobileAppTab) => onNavigate && links?.[id] === undefined ? undefined : destinations[id];

  return (
    <div
      className={styles.shell}
      data-layout-mode={mode}
      data-navigation-enabled={navigationEnabled ? "true" : "false"}
      data-official-ui-version={OFFICIAL_UI_V2_VERSION}
      data-shell-variant={variant}
    >
      <header className={styles.desktopHeader}>
        <Link className={styles.brand} href="/" aria-label="Pachangas IQ, Inicio">
          <Image src="/icon-192.png" alt="" width={36} height={36} priority unoptimized />
          <span><strong>Pachangas IQ</strong><small>{context.title}</small></span>
        </Link>
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
        {navigationEnabled ? <div className={styles.desktopUtilities}>
          <Link href="/ranking">Ranking</Link>
          <Link href="/perfil/avisos">Avisos</Link>
          <span aria-label={`Estado: ${context.status ?? "Conectado"}`}>{context.status ?? "Conectado"}</span>
        </div> : <span />}
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
          <div className={styles.gameUtilities}>
            <Link href="/perfil/avisos" aria-label="Avisos">AV</Link>
            <Link href="/ranking" aria-label="Ranking">RK</Link>
          </div>
        </aside> : null}

        <div className={styles.viewport}>
          <div className={styles.contextBar}>
            <div>
              <span>{context.eyebrow ?? "Pachangas IQ"}</span>
              <strong>{context.title}</strong>
              {context.detail ? <small>{context.detail}</small> : null}
            </div>
            <b>{context.status ?? "Conectado"}</b>
          </div>
          <div className={styles.content}>{children}</div>
        </div>
      </div>

      {navigationEnabled ? <div className={styles.portraitNav}>
        <MobileAppNav
          active={active}
          adminViewPreview={adminViewPreview}
          links={destinations}
          onNavigate={onNavigate}
        />
      </div> : null}
    </div>
  );
}
