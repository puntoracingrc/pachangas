"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { supabase } from "../supabaseClient";
import { ProvincialRankingBoard } from "./provincial-ranking-board";
import {
  type ProvincialOwnRank,
  type ProvincialRankingPayload,
} from "./provincial-ranking-contract";
import styles from "./ranking.module.css";

type CachedRanking = { payload: ProvincialRankingPayload; savedAt: string };

const provinceCode = "08";
const cachePointerKey = `pachangas:ranking:v1:latest:${provinceCode}`;

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function normalizeRanking(value: unknown): ProvincialRankingPayload {
  const root = record(value) ?? {};
  const items = (Array.isArray(root.items) ? root.items : []).flatMap((value) => {
    const item = record(value);
    const components = record(item?.components);
    if (!item || typeof item.entryKey !== "string") return [];
    return [{
      components: {
        competition: Number(components?.competition) || 0,
        opposition: Number(components?.opposition) || 0,
        quality: Number(components?.quality) || 0,
      },
      displayName: String(item.displayName ?? "Jugador"),
      entryKey: item.entryKey,
      logicalOpponents: Number(item.logicalOpponents) || 0,
      position: Number(item.position) || 0,
      score: Number(item.score) || 0,
      validChallenges: Number(item.validChallenges) || 0,
    }];
  });
  return {
    available: Boolean(root.available),
    items,
    pagination: record(root.pagination) as ProvincialRankingPayload["pagination"],
    publication: record(root.publication) as ProvincialRankingPayload["publication"],
    reason: typeof root.reason === "string" ? root.reason : undefined,
    season: record(root.season) as ProvincialRankingPayload["season"],
    territory: record(root.territory) as ProvincialRankingPayload["territory"],
  };
}

function normalizeOwnRank(value: unknown): ProvincialOwnRank {
  const root = record(value) ?? {};
  return {
    available: Boolean(root.available),
    displayName: typeof root.displayName === "string" ? root.displayName : undefined,
    entryKey: typeof root.entryKey === "string" ? root.entryKey : undefined,
    eligibilityState: root.eligibilityState === "eligible" || root.eligibilityState === "ineligible" || root.eligibilityState === "pending_integrity_review" || root.eligibilityState === "provisional"
      ? root.eligibilityState
      : undefined,
    logicalOpponents: Number(root.logicalOpponents) || 0,
    position: root.position === null ? null : Number(root.position) || undefined,
    provinceCode: typeof root.provinceCode === "string" ? root.provinceCode : undefined,
    publicationRevision: Number(root.publicationRevision) || 0,
    reason: typeof root.reason === "string" ? root.reason : undefined,
    reasonCodes: Array.isArray(root.reasonCodes) ? root.reasonCodes.map(String) : [],
    score: Number(root.score) || 0,
    validChallenges: Number(root.validChallenges) || 0,
  };
}

function cachedRanking(): CachedRanking | null {
  try {
    const pointer = JSON.parse(localStorage.getItem(cachePointerKey) ?? "null") as {
      revision?: number;
      seasonId?: string;
    } | null;
    if (!pointer?.seasonId || !pointer.revision) return null;
    const versionedKey = `pachangas:ranking:v1:${pointer.seasonId}:${provinceCode}:${pointer.revision}`;
    const parsed = JSON.parse(localStorage.getItem(versionedKey) ?? "null") as CachedRanking | null;
    return parsed?.payload && typeof parsed.savedAt === "string" ? parsed : null;
  } catch {
    return null;
  }
}

function formatPublishedAt(value?: string) {
  if (!value) return "Sin publicación";
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" })
    .format(new Date(value));
}

export function ProvincialRankingProduct({ embedded = false }: { embedded?: boolean } = {}) {
  const [ranking, setRanking] = useState<ProvincialRankingPayload | null>(null);
  const [ownRank, setOwnRank] = useState<ProvincialOwnRank | null>(null);
  const [loading, setLoading] = useState(true);
  const [cached, setCached] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async (quiet = false) => {
    if (!supabase) {
      setMessage("La conexión con el servidor no está configurada.");
      setLoading(false);
      return;
    }
    if (!quiet) setLoading(true);
    const rankingResult = await supabase.rpc("get_pachanga_provincial_ranking_v1", {
      page_offset: 0,
      page_size: 10,
      target_province_code: provinceCode,
    });
    if (rankingResult.error) {
      setMessage(navigator.onLine
        ? "No se ha podido actualizar la clasificación."
        : "Sin conexión. Mostrando la última clasificación guardada.");
      setLoading(false);
      return;
    }
    const next = normalizeRanking(rankingResult.data);
    setRanking(next);
    setCached(false);
    setMessage("");
    if (next.season?.id && next.publication?.revision) {
      try {
        const versionedKey = `pachangas:ranking:v1:${next.season.id}:${provinceCode}:${next.publication.revision}`;
        localStorage.setItem(versionedKey, JSON.stringify({ payload: next, savedAt: new Date().toISOString() }));
        localStorage.setItem(cachePointerKey, JSON.stringify({
          revision: next.publication.revision,
          seasonId: next.season.id,
        }));
      } catch {
        // The authoritative server snapshot remains usable when browser storage is unavailable.
      }
    }

    const ownResult = await supabase.rpc("get_my_pachanga_provincial_rank_v1", {
      target_season_id: next.season?.id ?? null,
    });
    setOwnRank(ownResult.error ? null : normalizeOwnRank(ownResult.data));
    setLoading(false);
  }, []);

  useEffect(() => {
    const task = window.setTimeout(() => {
      const saved = cachedRanking();
      if (saved) {
        setRanking(saved.payload);
        setCached(true);
        setLoading(false);
      }
      void load(Boolean(saved));
    }, 0);
    return () => window.clearTimeout(task);
  }, [load]);

  useEffect(() => {
    if (!supabase) return;
    const client = supabase;
    const channel = client.channel(`provincial-ranking-${provinceCode}`)
      .on("postgres_changes", {
        event: "*",
        filter: `province_code=eq.${provinceCode}`,
        schema: "public",
        table: "pachanga_provincial_ranking_publications",
      }, (event) => {
        const next = record(event.new);
        const revision = Number(next?.published_revision) || 0;
        if (revision !== (ranking?.publication?.revision ?? 0)) void load(true);
      })
      .subscribe();
    return () => { void client.removeChannel(channel); };
  }, [load, ranking?.publication?.revision]);

  const publishedLabel = formatPublishedAt(ranking?.publication?.publishedAt);

  const content = (
    <section className={styles.shell} data-official-surface="ranking">
      <header className={styles.topbar}>
        <div>
          {!embedded ? <Link href="/" className={styles.back}>Volver</Link> : null}
          <h1>Ranking provincial</h1>
        </div>
        <div className={styles.territory}>
          <span>Provincia</span>
          <strong>{ranking?.territory?.provinceName ?? "Barcelona"}</strong>
        </div>
      </header>

      <section className={styles.statusbar}>
        <div><span>Temporada</span><strong>{ranking?.season?.label ?? "Sin temporada activa"}</strong></div>
        <div><span>Fórmula</span><strong>55 Calidad · 30 Competición · 15 Oposición</strong></div>
        <div><span>Revisión</span><strong>{ranking?.publication?.revision ?? 0}</strong></div>
        <small>{cached ? "Caché confirmada" : publishedLabel}</small>
      </section>

      {message && <div className={styles.notice} role="status">{message}</div>}

      <ProvincialRankingBoard loading={loading} ownRank={ownRank} ranking={ranking} />
    </section>
  );
  if (embedded) return content;
  return (
    <OfficialProductShellV2
      active="equipo"
      context={{
        detail: ranking?.season?.label ?? "Sin temporada activa",
        eyebrow: "Competición",
        status: cached ? "Caché confirmada" : "En directo",
        title: "Ranking provincial",
      }}
    >
      {content}
    </OfficialProductShellV2>
  );
}
