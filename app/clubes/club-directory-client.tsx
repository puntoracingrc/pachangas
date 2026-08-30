"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { GamePageHeader, ProductFeedback, ResponsiveActionBar, SectionHeader, StatusChip } from "../_components/official-ui-v2-primitives";
import styles from "./club-directory.module.css";

type JsonRecord = Record<string, unknown>;
type DirectoryEnvelope = { enabled?: unknown; items?: unknown; page?: unknown; pageSize?: unknown; total?: unknown };

function record(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function array(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function text(value: unknown) { return typeof value === "string" ? value : ""; }
function number(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function areaLabel(value: unknown) {
  const area = record(value);
  return [text(area.municipality), text(area.province), text(area.countryCode)].filter(Boolean).join(" · ") || text(area.area) || "Zona no indicada";
}

export function ClubDirectoryClient({
  directoryEnabled,
  embedded = false,
  initialData = null,
}: {
  directoryEnabled?: boolean;
  embedded?: boolean;
  initialData?: DirectoryEnvelope | null;
}) {
  const [data, setData] = useState<DirectoryEnvelope>(initialData ?? {});
  const [query, setQuery] = useState("");
  const [zone, setZone] = useState("");
  const [clubType, setClubType] = useState("");
  const [verified, setVerified] = useState("");
  const [partner, setPartner] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const initialLoadStarted = useRef(false);
  const enabled = directoryEnabled ?? data.enabled === true;
  const items = useMemo(() => array(data.items), [data.items]);
  const page = Math.max(1, number(data.page) || 1);
  const pageSize = Math.max(1, number(data.pageSize) || 24);
  const total = Math.max(0, number(data.total));
  const pages = Math.max(1, Math.ceil(total / pageSize));

  const load = useCallback(async (nextPage = 1) => {
    const params = new URLSearchParams({ page: String(nextPage), pageSize: String(pageSize) });
    if (query.trim()) params.set("query", query.trim());
    if (zone.trim()) params.set("zone", zone.trim());
    if (clubType) params.set("type", clubType);
    if (verified) params.set("verified", verified);
    if (partner) params.set("partner", partner);
    setLoading(true);
    setMessage("");
    try {
      const response = await fetch(`/api/clubs/directory?${params.toString()}`, { cache: "no-store" });
      const body = await response.json() as DirectoryEnvelope & { error?: string };
      if (!response.ok) throw new Error(body.error || "No se pudo consultar el directorio.");
      setData(body);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo consultar el directorio.");
    } finally { setLoading(false); }
  }, [clubType, pageSize, partner, query, verified, zone]);

  useEffect(() => {
    if (initialData || initialLoadStarted.current) return;
    initialLoadStarted.current = true;
    void load(1);
  }, [initialData, load]);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void load(1);
  }

  const directory = (
    <section className={styles.surface} data-club-directory="beta">
      <div className={styles.betaLine}><StatusChip tone="info">BETA</StatusChip><span>Esta función está en beta. Puedes usarla con normalidad y ayudarnos a mejorarla.</span>{embedded ? <Link className={styles.betaAction} href="/clubes/gestionar">Crear Club</Link> : null}</div>
      {!enabled ? <ProductFeedback tone="info">El directorio de Clubs todavía no está activo.</ProductFeedback> : <>
        <form className={styles.filters} onSubmit={submit} aria-label="Filtros de Clubs">
          <label>Buscar<input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Nombre o zona" /></label>
          <label>Zona<input value={zone} onChange={(event) => setZone(event.target.value)} placeholder="Municipio o provincia" /></label>
          <label>Tipo<select value={clubType} onChange={(event) => setClubType(event.target.value)}><option value="">Todos</option><option value="FOOTBALL_CLUB">Club de fútbol</option><option value="SPORTS_CENTER">Centro deportivo</option><option value="ASSOCIATION">Asociación</option><option value="INDEPENDENT_ORGANIZER">Organizador</option><option value="OTHER">Otro</option></select></label>
          <label>Verificación<select value={verified} onChange={(event) => setVerified(event.target.value)}><option value="">Todas</option><option value="true">Verificado</option><option value="false">No verificado</option></select></label>
          <label>Partner<select value={partner} onChange={(event) => setPartner(event.target.value)}><option value="">Todos</option><option value="true">Partner</option><option value="false">No partner</option></select></label>
          <button type="submit" disabled={loading}>{loading ? "Buscando..." : "Aplicar"}</button>
        </form>
        {message ? <ProductFeedback tone="danger">{message}</ProductFeedback> : null}
        <div className={styles.resultHeader}><SectionHeader eyebrow={`${total} Club${total === 1 ? "" : "s"}`} title="Directorio público" /></div>
        <div className={styles.grid} aria-live="polite">
          {items.map((club) => {
            const name = text(club.name) || "Club";
            return <article className={styles.card} key={text(club.clubId) || text(club.slug)}>
              <div className={styles.identity}><span className={styles.logo}>{name.slice(0, 2).toUpperCase()}</span><div><small>{text(club.clubType).replaceAll("_", " ")}</small><h2>{name}</h2><p>{areaLabel(club.generalArea)}</p></div></div>
              <div className={styles.badges}>{club.verified ? <StatusChip tone="success">Verificado</StatusChip> : <StatusChip tone="neutral">No verificado</StatusChip>}{club.partner ? <StatusChip tone="warning">Partner</StatusChip> : null}</div>
              <p className={styles.description}>{text(club.description) || "Perfil público de Club en Pachangas IQ."}</p>
              <ResponsiveActionBar><Link href={`/clubes/${text(club.slug)}`}>Ver Club</Link><Link href={`/clubes/gestionar?requestClub=${encodeURIComponent(text(club.clubId))}&clubRevision=${number(club.revision)}&clubName=${encodeURIComponent(name)}`}>Vincular mi equipo</Link></ResponsiveActionBar>
            </article>;
          })}
        </div>
        {!loading && !items.length ? <p className={styles.empty}>No hay Clubs públicos con estos filtros.</p> : null}
        {pages > 1 ? <nav className={styles.pagination} aria-label="Páginas de Clubs"><button type="button" disabled={page <= 1 || loading} onClick={() => void load(page - 1)}>Anterior</button><span>{page} de {pages}</span><button type="button" disabled={page >= pages || loading} onClick={() => void load(page + 1)}>Siguiente</button></nav> : null}
      </>}
    </section>
  );

  if (embedded) return directory;
  return <OfficialProductShellV2 active="mercado" perspective="free-agent" context={{ detail: "Clubs activos y públicos", eyebrow: "Mercado · Clubs", status: enabled ? "BETA" : "Próximamente", title: "Clubs" }}><main className={styles.page} data-mobile-tab="mercado"><GamePageHeader actions={<><Link href="/clubes/gestionar">Crear Club</Link><Link href="/mercado?tab=clubes">Mercado</Link></>} eyebrow="Red deportiva" summary="Encuentra Clubs, asociaciones y organizadores con perfil público." title="Clubs" />{directory}</main></OfficialProductShellV2>;
}
