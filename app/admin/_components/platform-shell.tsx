"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { OFFICIAL_UI_V2_VERSION } from "../../_design-v2/official-ui-v2-contract";
import {
  hasPlatformCapability,
  platformNavigation,
  platformRoleLabels,
  type PlatformAccess,
  type PlatformEnvironment,
} from "../_lib/platform-contract";
import styles from "../platform-admin.module.css";

type SearchResult = {
  href: string;
  id: string;
  label: string;
  secondary?: string;
  type: string;
};

export function PlatformShell({
  access,
  children,
  environment,
}: {
  access: PlatformAccess;
  children: ReactNode;
  environment: PlatformEnvironment;
}) {
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const requestId = useRef(0);
  const allowedNavigation = platformNavigation.filter((item) => hasPlatformCapability(access, item.capability));

  useEffect(() => {
    const normalized = query.trim();
    if (normalized.length < 2 || !hasPlatformCapability(access, "search.read")) {
      return;
    }
    const currentRequest = ++requestId.current;
    const timeout = window.setTimeout(async () => {
      setSearching(true);
      try {
        const response = await fetch(`/api/platform-admin/search?q=${encodeURIComponent(normalized)}`, { cache: "no-store" });
        const body = await response.json() as { items?: SearchResult[] };
        if (requestId.current === currentRequest) setResults(response.ok ? body.items ?? [] : []);
      } catch {
        if (requestId.current === currentRequest) setResults([]);
      } finally {
        if (requestId.current === currentRequest) setSearching(false);
      }
    }, 220);
    return () => window.clearTimeout(timeout);
  }, [access, query]);

  return (
    <div
      className={styles.adminRoot}
      data-official-ui-version={OFFICIAL_UI_V2_VERSION}
      data-shell-variant="PLATFORM_ADMIN"
    >
      <header className={styles.mobileBar}>
        <button
          className={styles.iconButton}
          type="button"
          aria-label={menuOpen ? "Cerrar menú" : "Abrir menú"}
          aria-expanded={menuOpen}
          onClick={() => setMenuOpen((current) => !current)}
        >
          {menuOpen ? "×" : "☰"}
        </button>
        <strong>Control Center</strong>
        <span className={`${styles.environmentBadge} ${styles[`environment${environment}`]}`}>{environment}</span>
      </header>

      {menuOpen ? <button className={styles.drawerBackdrop} type="button" aria-label="Cerrar menú" onClick={() => setMenuOpen(false)} /> : null}
      <aside className={`${styles.sidebar} ${menuOpen ? styles.sidebarOpen : ""}`}>
        <div className={styles.brand}>
          <Image src="/icon-192.png" alt="" width={38} height={38} priority unoptimized />
          <div>
            <strong>Pachangas IQ</strong>
            <span>Control Center</span>
          </div>
        </div>
        <span className={`${styles.environmentBadge} ${styles[`environment${environment}`]}`}>{environment}</span>
        <nav aria-label="Control Center">
          {allowedNavigation.map((item) => {
            const exactHome = item.href === "/admin";
            const selected = exactHome ? pathname === item.href : pathname.startsWith(item.href);
            return (
              <Link className={selected ? styles.navActive : ""} href={item.href} key={item.href} aria-current={selected ? "page" : undefined} onClick={() => setMenuOpen(false)}>
                {item.label}
              </Link>
            );
          })}
        </nav>
        <div className={styles.sidebarFooter}>
          <span>{platformRoleLabels[access.role]}</span>
          {access.role === "platform_owner" ? <Link href="/admin/demo">Mundo Demo completo</Link> : null}
          <Link href="/">Ver como usuario</Link>
        </div>
      </aside>

      <div className={styles.workspace}>
        <header className={styles.topbar}>
          <div className={styles.searchWrap}>
            <label htmlFor="platform-search">Buscar en Pachangas IQ</label>
            <div className={styles.searchField}>
              <span aria-hidden="true">⌕</span>
              <input
                id="platform-search"
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Usuario, equipo, club, partido, Reto, caso o Stripe..."
                autoComplete="off"
              />
              {searching ? <span className={styles.searching}>Buscando</span> : null}
            </div>
            {query.trim().length >= 2 ? (
              <div className={styles.searchResults} role="listbox" aria-label="Resultados globales">
                {results.length ? results.map((result) => (
                  <Link href={result.href} key={`${result.type}:${result.id}`} onClick={() => setQuery("")}>
                    <span>{result.label}</span>
                    <small>{result.type}{result.secondary ? ` · ${result.secondary}` : ""}</small>
                  </Link>
                )) : !searching ? <p>Sin resultados</p> : null}
              </div>
            ) : null}
          </div>
          <div className={styles.topbarMeta}>
            <span>{platformRoleLabels[access.role]}</span>
            <code>{access.userId.slice(0, 8)}</code>
          </div>
        </header>
        <main className={styles.adminMain}>{children}</main>
      </div>
    </div>
  );
}
