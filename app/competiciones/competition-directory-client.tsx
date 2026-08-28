"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { GamePageHeader, ProductFeedback, SectionHeader, StatusChip } from "../_components/official-ui-v2-primitives";
import {
  publicCompetitionArray,
  publicCompetitionNumber,
  publicCompetitionRecord,
  publicCompetitionSportLabel,
  publicCompetitionStateLabel,
  publicCompetitionText,
  publicCompetitionTypeLabel,
} from "../public-competition-contract";
import styles from "./public-competitions.module.css";

const cacheKey = "pachangas-public-competition-directory-v1";

function loadCache() {
  try {
    const value = publicCompetitionRecord(JSON.parse(window.localStorage.getItem(cacheKey) ?? "null"));
    return Date.now() - publicCompetitionNumber(value.storedAt) < 24 * 60 * 60 * 1000
      ? publicCompetitionRecord(value.data)
      : null;
  } catch { return null; }
}

function storeCache(data: Record<string, unknown>) {
  try { window.localStorage.setItem(cacheKey, JSON.stringify({ data, storedAt: Date.now() })); } catch {
    // Derived public cache only. PostgreSQL remains authoritative.
  }
}

function dateLabel(value: unknown) {
  const source = publicCompetitionText(value);
  if (!source) return "Fecha por confirmar";
  return new Intl.DateTimeFormat("es-ES", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(source));
}

export function CompetitionDirectoryClient({
  embedded = false,
  initialData,
  onOpen,
}: {
  embedded?: boolean;
  initialData: Record<string, unknown> | null;
  onOpen?: (slug: string) => void;
}) {
  const [data, setData] = useState<Record<string, unknown>>(initialData ?? {});
  const [search, setSearch] = useState("");
  const [type, setType] = useState("");
  const [sportFormat, setSportFormat] = useState("");
  const [state, setState] = useState("");
  const [registration, setRegistration] = useState("");
  const [area, setArea] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const page = Math.max(1, publicCompetitionNumber(data.page) || 1);
  const pageSize = Math.max(1, publicCompetitionNumber(data.pageSize) || 24);
  const total = Math.max(0, publicCompetitionNumber(data.total));
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const items = useMemo(() => publicCompetitionArray(data.items), [data.items]);

  useEffect(() => { if (initialData && !embedded) storeCache(initialData); }, [embedded, initialData]);

  const load = useCallback(async (nextPage: number) => {
    if (embedded) {
      const normalizedSearch = search.trim().toLocaleLowerCase("es");
      const normalizedArea = area.trim().toLocaleLowerCase("es");
      const sourceItems = publicCompetitionArray(initialData?.items);
      const filtered = sourceItems.filter((item) => {
        const competition = publicCompetitionRecord(item.competition);
        const publication = publicCompetitionRecord(item.publication);
        const organizer = publicCompetitionRecord(item.organizer);
        const category = publicCompetitionRecord(item.category);
        const registrationData = publicCompetitionRecord(item.registration);
        const haystack = [competition.name, competition.description, organizer.name]
          .map(publicCompetitionText).join(" ").toLocaleLowerCase("es");
        const areaValue = [competition.municipality, competition.generalArea]
          .map(publicCompetitionText).join(" ").toLocaleLowerCase("es");
        return (!normalizedSearch || haystack.includes(normalizedSearch))
          && (!normalizedArea || areaValue.includes(normalizedArea))
          && (!type || publicCompetitionText(competition.type) === type)
          && (!sportFormat || publicCompetitionText(category.sportFormat) === sportFormat)
          && (!state || publicCompetitionText(competition.publicState) === state)
          && (!registration || publicCompetitionText(registrationData.state) === registration)
          && publicCompetitionText(publication.status) === "published";
      });
      setData({ ...(initialData ?? {}), items: filtered, page: 1, total: filtered.length });
      return;
    }
    const params = new URLSearchParams({ page: String(nextPage), pageSize: String(pageSize) });
    if (search.trim()) params.set("search", search.trim());
    if (type) params.set("type", type);
    if (sportFormat) params.set("sportFormat", sportFormat);
    if (state) params.set("state", state);
    if (registration) params.set("registration", registration);
    if (area.trim()) params.set("area", area.trim());
    setLoading(true); setMessage("");
    try {
      const response = await fetch(`/api/competitions/public/directory?${params.toString()}`);
      const body = publicCompetitionRecord(await response.json());
      if (!response.ok) throw new Error(publicCompetitionText(body.error) || "No se pudo abrir el directorio.");
      setData(body); storeCache(body);
    } catch (error) {
      const cached = loadCache();
      if (cached) { setData(cached); setMessage("Sin conexión. Mostrando el último directorio guardado."); }
      else setMessage(error instanceof Error ? error.message : "No se pudo abrir el directorio.");
    } finally { setLoading(false); }
  }, [area, embedded, initialData, pageSize, registration, search, sportFormat, state, type]);

  function submit(event: FormEvent<HTMLFormElement>) { event.preventDefault(); void load(1); }

  const content = <div className={styles.page} data-mobile-tab="mercado" data-product-renderer="public-competition-directory">
      <GamePageHeader actions={<><Link href="/ligas">Mis Ligas</Link><Link href="/torneos">Mis Torneos</Link></>} eyebrow="Directorio público" summary="Calendarios, resultados y solicitudes confirmados por el servidor central." title="Competiciones" />
      <form className={styles.filters} onSubmit={submit} aria-label="Filtros de competiciones">
        <label className={styles.search}>Buscar<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Nombre u organizador" /></label>
        <label>Tipo<select value={type} onChange={(event) => setType(event.target.value)}><option value="">Todos</option><option value="LEAGUE">Liga</option><option value="TOURNAMENT">Torneo</option></select></label>
        <label>Modalidad<select value={sportFormat} onChange={(event) => setSportFormat(event.target.value)}><option value="">Todas</option><option value="FOOTBALL_5">Fútbol 5</option><option value="FOOTBALL_7">Fútbol 7</option><option value="FOOTBALL_11">Fútbol 11</option><option value="FUTSAL">Fútbol sala</option></select></label>
        <label>Estado<select value={state} onChange={(event) => setState(event.target.value)}><option value="">Todos</option><option value="UPCOMING">Próximamente</option><option value="REGISTRATION_OPEN">Inscripción abierta</option><option value="IN_PROGRESS">En curso</option><option value="FINISHED">Finalizada</option></select></label>
        <label>Registro<select value={registration} onChange={(event) => setRegistration(event.target.value)}><option value="">Todos</option><option value="OPEN">Con plazas</option><option value="WAITLIST">Lista de espera</option><option value="CLOSED">Cerrado</option></select></label>
        <label>Zona<input value={area} onChange={(event) => setArea(event.target.value)} placeholder="Municipio o área" /></label>
        <button type="submit" disabled={loading}>{loading ? "Buscando..." : "Aplicar"}</button>
      </form>
      {message ? <ProductFeedback tone={/Sin conexión/i.test(message) ? "warning" : "danger"}>{message}</ProductFeedback> : null}
      <SectionHeader eyebrow={`${total} resultado${total === 1 ? "" : "s"}`} title="Ligas y Torneos" />
      <section className={styles.grid} aria-live="polite">
        {items.map((item) => {
          const competition = publicCompetitionRecord(item.competition);
          const publication = publicCompetitionRecord(item.publication);
          const registrationData = publicCompetitionRecord(item.registration);
          const organizer = publicCompetitionRecord(item.organizer);
          const category = publicCompetitionRecord(item.category);
          const name = publicCompetitionText(competition.name) || "Competición";
          const image = publicCompetitionText(competition.image);
          const available = publicCompetitionNumber(registrationData.availablePlaces);
          return <article className={styles.card} key={publicCompetitionText(publication.id) || publicCompetitionText(publication.slug)}>
            <div className={styles.visual}>{image ? <Image src={image} alt="" fill sizes="(max-width: 620px) 100vw, 33vw" unoptimized /> : <span>{publicCompetitionTypeLabel(competition.type).slice(0, 2).toUpperCase()}</span>}<b>{publicCompetitionTypeLabel(competition.type)}</b></div>
            <div className={styles.cardBody}>
              <div className={styles.chips}><StatusChip tone="info">{publicCompetitionSportLabel(category.sportFormat)}</StatusChip><StatusChip tone={publicCompetitionText(competition.publicState) === "REGISTRATION_OPEN" ? "success" : "neutral"}>{publicCompetitionStateLabel(competition.publicState)}</StatusChip></div>
              <h2>{name}</h2>
              <p>{publicCompetitionText(organizer.name)} · {publicCompetitionText(competition.municipality) || publicCompetitionText(competition.generalArea) || "Zona por confirmar"}</p>
              <dl><div><dt>Inicio</dt><dd>{dateLabel(competition.startsAt)}</dd></div><div><dt>Formato</dt><dd>{publicCompetitionText(competition.format) || publicCompetitionTypeLabel(competition.type)}</dd></div><div><dt>Plazas</dt><dd>{available > 0 ? available : publicCompetitionText(registrationData.state) === "WAITLIST" ? "Espera" : "Completo"}</dd></div></dl>
              {onOpen ? <button className={styles.open} type="button" onClick={() => onOpen(publicCompetitionText(publication.slug))}>Ver competición</button> : <Link className={styles.open} href={`/competiciones/${publicCompetitionText(publication.slug)}`}>Ver competición</Link>}
            </div>
          </article>;
        })}
      </section>
      {!loading && !items.length ? <p className={styles.empty}>No hay competiciones públicas con estos filtros.</p> : null}
      {pages > 1 ? <nav className={styles.pagination} aria-label="Páginas de competiciones"><button type="button" disabled={page <= 1 || loading} onClick={() => void load(page - 1)}>Anterior</button><span>{page} de {pages}</span><button type="button" disabled={page >= pages || loading} onClick={() => void load(page + 1)}>Siguiente</button></nav> : null}
    </div>;
  return embedded ? content : <OfficialProductShellV2 active="mercado" context={{ detail: `${total} competiciones públicas`, eyebrow: "Mercado deportivo", status: "BETA", title: "Competiciones" }}>{content}</OfficialProductShellV2>;
}
