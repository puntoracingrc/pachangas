"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { RefereeProfileCard } from "../_components/referee-profile-card";
import { ProductFeedback, ResponsiveActionBar, SectionHeader, StatusChip } from "../_components/official-ui-v2-primitives";
import { clientWriteFetch } from "../pwa-client-bridge";
import {
  refereeArray,
  refereeNumber,
  refereeText,
  type RefereeJson,
} from "../referee-platform-contract";
import { supabase } from "../supabaseClient";
import styles from "./referee-marketplace-panel.module.css";

type RefereeMatchContext = {
  groupId: string;
  matchId: string;
  title: string;
};

type MarketplaceResponse = {
  items?: unknown;
  page?: unknown;
  pageSize?: unknown;
  total?: unknown;
};

const modalityOptions = [
  ["", "Todas"],
  ["FOOTBALL_11", "Fútbol 11"],
  ["FOOTBALL_7", "Fútbol 7"],
  ["FOOTBALL_5", "Fútbol 5"],
  ["FUTSAL", "Fútbol sala"],
  ["OTHER", "Otra"],
] as const;

const availabilityOptions = [
  ["", "Todas"],
  ["AVAILABLE", "Disponible"],
  ["LIMITED", "Limitada"],
  ["UNAVAILABLE", "No disponible"],
] as const;

function queryFromForm(form: HTMLFormElement) {
  const data = new FormData(form);
  const query = new URLSearchParams({ page: "1", pageSize: "18" });
  for (const key of ["zone", "province", "municipality", "modality", "weekday", "startTime", "endTime", "availability", "club", "experienceSince", "verified"]) {
    const value = String(data.get(key) ?? "").trim();
    if (value) query.set(key, value);
  }
  return query;
}

export function RefereeMarketplacePanel({
  canPropose,
  context,
  previewItems,
}: {
  canPropose: boolean;
  context: RefereeMatchContext | null;
  previewItems?: RefereeJson[];
}) {
  const [accessToken, setAccessToken] = useState("");
  const [items, setItems] = useState<RefereeJson[]>(previewItems ?? []);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(18);
  const [total, setTotal] = useState(previewItems?.length ?? 0);
  const [query, setQuery] = useState(() => new URLSearchParams({ page: "1", pageSize: "18" }));
  const [loading, setLoading] = useState(!previewItems);
  const [message, setMessage] = useState("");
  const [pendingProfile, setPendingProfile] = useState("");
  const [selectedProfileId, setSelectedProfileId] = useState(() => refereeText(previewItems?.[0]?.refereeProfileId));

  useEffect(() => {
    if (previewItems) return;
    let active = true;
    void supabase?.auth.getSession().then(({ data }) => {
      if (!active) return;
      setAccessToken(data.session?.access_token ?? "");
    });
    return () => { active = false; };
  }, [previewItems]);

  const load = useCallback(async (nextQuery: URLSearchParams, token: string) => {
    if (!token) {
      setItems([]);
      setLoading(false);
      setMessage("Inicia sesión para consultar árbitros disponibles.");
      return;
    }
    setLoading(true);
    try {
      const response = await fetch(`/api/referees/market?${nextQuery.toString()}`, {
        cache: "no-store",
        headers: { Authorization: `Bearer ${token}` },
      });
      const body = await response.json() as MarketplaceResponse & { message?: string };
      if (!response.ok) throw new Error(body.message || "No se pudo consultar el mercado arbitral.");
      setItems(refereeArray(body.items));
      setPage(Math.max(1, refereeNumber(body.page)));
      setPageSize(Math.max(1, refereeNumber(body.pageSize)));
      setTotal(Math.max(0, refereeNumber(body.total)));
      setMessage("");
    } catch (error) {
      setItems([]);
      setMessage(error instanceof Error ? error.message : "No se pudo consultar el mercado arbitral.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (previewItems) return;
    const timer = window.setTimeout(() => void load(query, accessToken), 0);
    return () => window.clearTimeout(timer);
  }, [accessToken, load, previewItems, query]);

  function submitFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setQuery(queryFromForm(event.currentTarget));
  }

  function movePage(nextPage: number) {
    const next = new URLSearchParams(query);
    next.set("page", String(nextPage));
    setQuery(next);
  }

  async function propose(profile: RefereeJson) {
    const profileId = refereeText(profile.refereeProfileId);
    if (!context || !canPropose || !profileId || !accessToken) return;
    setPendingProfile(profileId);
    setMessage("Enviando la propuesta al servidor...");
    try {
      const response = await clientWriteFetch("api:referee-command", "/api/referees/command", {
        body: JSON.stringify({
          action: "assignment.propose",
          aggregateId: crypto.randomUUID(),
          expectedRevision: 0,
          operationId: crypto.randomUUID(),
          payload: {
            assignmentRole: "MAIN_REFEREE",
            message: `Propuesta para arbitrar ${context.title}`,
            reason: "referee_marketplace_assignment_proposal",
            refereeProfileId: profileId,
            requesterId: context.groupId,
            requesterKind: "TEAM",
            sourceGroupId: context.groupId,
            sourceId: context.matchId,
            sourceKind: "group_match",
          },
        }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as { message?: string };
      if (!response.ok) throw new Error(body.message || "La propuesta no ha sido confirmada.");
      setMessage(`Propuesta confirmada para ${refereeText(profile.displayName) || "el árbitro"}.`);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "La propuesta no ha sido confirmada.");
    } finally {
      setPendingProfile("");
    }
  }

  const lastPage = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [pageSize, total]);
  const selectedProfile = items.find((item) => refereeText(item.refereeProfileId) === selectedProfileId) ?? items[0] ?? null;
  const resolvedSelectedProfileId = refereeText(selectedProfile?.refereeProfileId);

  return (
    <section className={styles.surface} aria-label="Mercado de árbitros" data-referee-market-v2="true">
      <form className={styles.filters} onSubmit={submitFilters} aria-label="Filtros de árbitros">
        <SectionHeader eyebrow="Mercado" title="Filtros" />
        <label>Zona<input name="zone" placeholder="Barcelona, Vallès..." /></label>
        <label>Provincia<input name="province" placeholder="Barcelona" /></label>
        <label>Municipio<input name="municipality" placeholder="Sabadell" /></label>
        <label>Modalidad<select name="modality">{modalityOptions.map(([value, label]) => <option key={value || "all"} value={value}>{label}</option>)}</select></label>
        <label>Día<select name="weekday"><option value="">Todos</option>{["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"].map((label, index) => <option key={label} value={index + 1}>{label}</option>)}</select></label>
        <label>Desde<input name="startTime" type="time" /></label>
        <label>Hasta<input name="endTime" type="time" /></label>
        <label>Disponibilidad<select name="availability">{availabilityOptions.map(([value, label]) => <option key={value || "all"} value={value}>{label}</option>)}</select></label>
        <label>Club vinculado<input name="club" placeholder="ID del Club" /></label>
        <label>Experiencia desde<input name="experienceSince" type="number" min="1950" max={new Date().getFullYear()} /></label>
        <label>Verificación<select name="verified"><option value="">Todas</option><option value="true">Verificado</option><option value="false">No verificado</option></select></label>
        <button type="submit">Aplicar filtros</button>
      </form>

      <div className={styles.resultsPane}>
        <SectionHeader eyebrow={`${total} resultado${total === 1 ? "" : "s"}`} title="Árbitros disponibles" />
        {context ? <ProductFeedback tone="info">Propuesta para <strong>{context.title}</strong>. Solo el owner del equipo puede enviarla.</ProductFeedback> : null}
        {message ? <ProductFeedback tone={/confirmada/i.test(message) ? "success" : /no |error/i.test(message) ? "danger" : "warning"}>{message}</ProductFeedback> : null}
        {loading ? <p className={styles.empty}>Consultando el estado canónico...</p> : null}
        {!loading && !items.length ? <p className={styles.empty}>No hay árbitros que encajen con estos filtros.</p> : null}

        <div className={styles.grid} role="group" aria-label="Resultados del mercado arbitral">
          {items.map((profile) => {
            const profileId = refereeText(profile.refereeProfileId);
            const selected = resolvedSelectedProfileId === profileId;
            return <article className={styles.result} data-selected={selected || undefined} key={profileId || refereeText(profile.slug)}>
              <button aria-pressed={selected} className={styles.selector} type="button" onClick={() => setSelectedProfileId(profileId)}>
                <span>{refereeText(profile.displayName) || "Árbitro"}</span>
                <small>{refereeText(profile.availabilityStatus).replaceAll("_", " ") || "Sin disponibilidad"}</small>
                <StatusChip tone={refereeText(profile.verificationStatus) === "verified" ? "success" : "neutral"}>{refereeText(profile.verificationStatus) === "verified" ? "Verificado" : "Perfil"}</StatusChip>
              </button>
              <div className={styles.cardResult}><RefereeProfileCard compact profile={profile} />
                <ResponsiveActionBar className={styles.actions}>
                  <Link href={`/arbitros/${refereeText(profile.slug)}`}>Ver ficha</Link>
                  <button type="button" disabled={!canPropose || !context || pendingProfile === profileId} onClick={() => void propose(profile)}>{pendingProfile === profileId ? "Enviando..." : context ? "Proponer arbitraje" : "Abre un partido para proponer"}</button>
                </ResponsiveActionBar>
              </div>
            </article>;
          })}
        </div>

        {total > pageSize ? <nav className={styles.pagination} aria-label="Páginas de árbitros">
          <button type="button" disabled={page <= 1} onClick={() => movePage(page - 1)}>Anterior</button>
          <span>{page} de {lastPage} · {total} árbitros</span>
          <button type="button" disabled={page >= lastPage} onClick={() => movePage(page + 1)}>Siguiente</button>
        </nav> : null}
      </div>

      <aside className={styles.detailPane} aria-label="Detalle y propuesta">
        <SectionHeader eyebrow="Selección" title={selectedProfile ? refereeText(selectedProfile.displayName) || "Árbitro" : "Sin selección"} />
        {selectedProfile ? <><RefereeProfileCard adaptive compact profile={selectedProfile} /><ResponsiveActionBar className={styles.detailActions}><Link href={`/arbitros/${refereeText(selectedProfile.slug)}`}>Ver ficha</Link><button type="button" disabled={!canPropose || !context || pendingProfile === refereeText(selectedProfile.refereeProfileId)} onClick={() => void propose(selectedProfile)}>{pendingProfile === refereeText(selectedProfile.refereeProfileId) ? "Enviando..." : "Proponer"}</button></ResponsiveActionBar></> : <p className={styles.empty}>Selecciona un árbitro.</p>}
      </aside>
    </section>
  );
}
