"use client";

import Link from "next/link";
import { useCallback, useMemo, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import {
  venueArray,
  venueRecord,
  venueText,
  venueTextArray,
  venueNumber,
  VENUE_ENVIRONMENTS,
  VENUE_MODALITIES,
  VENUE_SURFACES,
  type VenueJson,
} from "../venue-operations-contract";
import styles from "../venue-operations.module.css";

function titleCase(value: unknown) {
  return venueText(value).replaceAll("_", " ").toLocaleLowerCase("es-ES");
}

export function VenueDirectoryClient({
  directoryEnabled,
  initialData,
}: {
  directoryEnabled: boolean;
  initialData: VenueJson | null;
}) {
  const [data, setData] = useState<VenueJson>(initialData ?? { items: [], page: 1, pageSize: 24, total: 0 });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [clubId, setClubId] = useState("");
  const items = useMemo(() => venueArray(data.items), [data.items]);
  const clubs = useMemo(() => {
    const result = new Map<string, string>();
    for (const item of items) {
      const club = venueRecord(item.club);
      if (venueText(club.clubId)) result.set(venueText(club.clubId), venueText(club.name) || "Club");
    }
    return [...result.entries()];
  }, [items]);
  const page = Math.max(1, venueNumber(data.page) || 1);
  const pageSize = Math.max(1, venueNumber(data.pageSize) || 24);
  const total = Math.max(0, venueNumber(data.total));
  const pages = Math.max(1, Math.ceil(total / pageSize));

  const load = useCallback(async (nextPage: number, form?: HTMLFormElement) => {
    const values = form ? new FormData(form) : null;
    const params = new URLSearchParams({ page: String(nextPage), pageSize: String(pageSize) });
    if (values) {
      for (const key of ["municipality", "modality", "environment", "surface", "date", "startTime", "endTime"]) {
        const value = String(values.get(key) ?? "").trim();
        if (value) params.set(key, value);
      }
      for (const key of ["lighting", "changingRooms", "accessible"]) {
        if (values.get(key) === "on") params.set(key, "true");
      }
    }
    if (clubId) params.set("clubId", clubId);
    setLoading(true);
    setMessage("");
    try {
      const response = await fetch("/api/venues/directory?" + params.toString(), { cache: "no-store" });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.error) || "No se pudo consultar Campos.");
      setData(body);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo consultar Campos.");
    } finally {
      setLoading(false);
    }
  }, [clubId, pageSize]);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void load(1, event.currentTarget);
  }

  return <OfficialProductShellV2
    active="mercado"
    perspective="free-agent"
    context={{ detail: "Disponibilidad pública canónica", eyebrow: "Mercado · Campos", status: directoryEnabled ? "En directo" : "Próximamente", title: "Campos" }}
  >
    <main className={styles.page} data-mobile-tab="mercado">
      <header className={styles.hero}>
        <div><span className={styles.eyebrow}>Instalaciones deportivas</span><h1>Campos</h1><p>Consulta superficies, servicios y franjas publicadas por cada Club.</p></div>
        <Link className={styles.secondaryAction} href="/reservas">Mis reservas</Link>
      </header>
      <section className={styles.surface}>
        {!directoryEnabled ? <p className={styles.empty}>El directorio público de Campos todavía no está activo.</p> : <>
          <form className={styles.filters} onSubmit={submit} aria-label="Filtros de Campos">
            <label>Municipio<input name="municipality" placeholder="Barcelona" /></label>
            <label>Modalidad<select name="modality" defaultValue=""><option value="">Todas</option>{VENUE_MODALITIES.map((item) => <option key={item} value={item}>{item === "FUTSAL" ? "Fútbol sala" : item}</option>)}</select></label>
            <label>Fecha<input name="date" type="date" /></label>
            <label>Desde<input name="startTime" type="time" /></label>
            <label>Hasta<input name="endTime" type="time" /></label>
            <label>Entorno<select name="environment" defaultValue=""><option value="">Todos</option>{VENUE_ENVIRONMENTS.map((item) => <option key={item} value={item}>{titleCase(item)}</option>)}</select></label>
            <label>Superficie<select name="surface" defaultValue=""><option value="">Todas</option>{VENUE_SURFACES.map((item) => <option key={item} value={item}>{titleCase(item)}</option>)}</select></label>
            <label>Club<select value={clubId} onChange={(event) => setClubId(event.target.value)}><option value="">Todos</option>{clubs.map(([id, name]) => <option key={id} value={id}>{name}</option>)}</select></label>
            <label className={styles.filterToggle}><input name="lighting" type="checkbox" />Iluminación</label>
            <label className={styles.filterToggle}><input name="changingRooms" type="checkbox" />Vestuarios</label>
            <label className={styles.filterToggle}><input name="accessible" type="checkbox" />Accesible</label>
            <button type="submit" disabled={loading}>{loading ? "Consultando..." : "Aplicar filtros"}</button>
          </form>
          {message ? <p className={styles.message} data-tone="danger">{message}</p> : null}
          <div className={styles.directoryHeader}><div><span className={styles.eyebrow}>Disponibles</span><strong>{total} instalación{total === 1 ? "" : "es"}</strong></div><small className={styles.muted}>La ubicación exacta solo se muestra tras una reserva confirmada.</small></div>
          <div className={styles.directoryGrid} aria-live="polite">
            {items.map((venue) => {
              const club = venueRecord(venue.club);
              const pitches = venueArray(venue.pitches);
              return <article className={styles.venueCard} key={venueText(venue.venueId)}>
                <div><span className={styles.eyebrow}>{venueText(club.name) || "Club"}</span><h2>{venueText(venue.name) || "Campo"}</h2><p>{[venueText(venue.municipality), venueText(venue.generalArea)].filter(Boolean).join(" · ") || "Zona general"}</p></div>
                <div className={styles.chips}>{pitches.flatMap((pitch) => venueTextArray(pitch.modalities)).filter((item, index, all) => item && all.indexOf(item) === index).map((item) => <span className={styles.chip} key={item}>{item === "FUTSAL" ? "Fútbol sala" : item}</span>)}</div>
                <p>{venueText(venue.description) || pitches.length + " pista" + (pitches.length === 1 ? "" : "s") + " publicada" + (pitches.length === 1 ? "" : "s") + "."}</p>
                <Link className={styles.action} href={"/campos/" + venueText(venue.slug)}>Ver disponibilidad</Link>
              </article>;
            })}
          </div>
          {!loading && !items.length ? <p className={styles.empty}>Todavía no hay Campos públicos con estos filtros.</p> : null}
          {pages > 1 ? <nav className={styles.pagination} aria-label="Páginas de Campos"><button className={styles.secondaryAction} type="button" disabled={page <= 1 || loading} onClick={() => void load(page - 1)}>Anterior</button><span>{page} de {pages}</span><button className={styles.secondaryAction} type="button" disabled={page >= pages || loading} onClick={() => void load(page + 1)}>Siguiente</button></nav> : null}
        </>}
      </section>
    </main>
  </OfficialProductShellV2>;
}
