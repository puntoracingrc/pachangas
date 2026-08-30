"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState, type ReactNode } from "react";
import { MobileAppNav, type AdminViewPreviewControl, type MobileAppTab } from "../mobile-app-nav";
import { ProductContextSelector, type ProductContextOption } from "./product-context-selector";
import {
  PRODUCT_PRIMARY_DESTINATIONS,
  contextualDestinationsForPerspective,
  type ProductActorPerspective,
} from "./product-navigation-contract";
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

type OfficialProductShellV2Props = {
  active: MobileAppTab;
  adminViewPreview?: AdminViewPreviewControl;
  children: ReactNode;
  context: OfficialContext;
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
  contextOptions,
  links,
  navigationEnabled = true,
  onContextChange,
  onNavigate,
  perspective = "player",
  variant = "PRODUCT",
}: OfficialProductShellV2Props) {
  const mode = useOfficialLayoutMode();
  const destinations = { ...defaultLinks, ...links };
  const contextualDestinations = contextualDestinationsForPerspective(perspective);
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
          {contextualDestinations.slice(0, 4).map((item) => <Link href={item.href} key={item.id}>{item.label}</Link>)}
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
            {contextualDestinations.slice(0, 4).map((item) => <Link href={item.href} key={item.id} aria-label={item.label}>{item.short}</Link>)}
          </div>
        </aside> : null}

        <div className={styles.viewport}>
          <div className={styles.contextBar}>
            <ProductContextSelector activeId={context.id ?? resolvedContexts[0]!.id} contexts={resolvedContexts} onChange={onContextChange} />
          </div>
          <div className={styles.content}>{children}</div>
        </div>
      </div>

      {navigationEnabled ? <div className={styles.portraitNav}>
        <MobileAppNav
          active={active}
          adminViewPreview={adminViewPreview}
          links={onNavigate ? links : destinations}
          onNavigate={onNavigate}
        />
      </div> : null}
    </div>
  );
}
