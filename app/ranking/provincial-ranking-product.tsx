"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "../supabaseClient";
import styles from "./ranking.module.css";

type RankingItem = {
  components: { competition: number; opposition: number; quality: number };
  displayName: string;
  entryKey: string;
  logicalOpponents: number;
  position: number;
  score: number;
  validChallenges: number;
};

type RankingPayload = {
  available: boolean;
  items: RankingItem[];
  pagination?: { offset: number; pageSize: number; total: number };
  publication?: { checksum: string; publishedAt: string; revision: number };
  reason?: string;
  season?: {
    endsAt: string;
    formulaKey: string;
    formulaVersion: number;
    id: string;
    key: string;
    label: string;
    startsAt: string;
    status: string;
  };
  territory?: { provinceCode: string; provinceName: string };
};

type OwnRank = {
  available: boolean;
  displayName?: string;
  eligibilityState?: string;
  logicalOpponents?: number;
  position?: number | null;
  provinceCode?: string;
  publicationRevision?: number;
  reason?: string;
  reasonCodes?: string[];
  score?: number;
  validChallenges?: number;
};

type CachedRanking = { payload: RankingPayload; savedAt: string };

const provinceCode = "08";
const cachePointerKey = `pachangas:ranking:v1:latest:${provinceCode}`;

const reasonLabels: Record<string, string> = {
  NO_PUBLISHED_POSITION: "Aún no tienes una posición publicada.",
  PLAYER_PROFILE_REQUIRED: "Completa tu ficha para entrar en la clasificación.",
  RANKING_NOT_ACTIVE: "La clasificación provincial todavía no está activa.",
  READ_MODEL_UNAVAILABLE: "La clasificación se está preparando.",
  TERRITORY_NOT_AVAILABLE: "Esta provincia todavía no está disponible.",
  ranking_evidence_incomplete: "Necesitas más retos y rivales válidos.",
  ranking_review_pending: "Tu clasificación está en revisión.",
  ranking_territory_pending: "Falta verificar el territorio competitivo.",
  rating_reliability_incomplete: "Tu ficha necesita mayor fiabilidad.",
  recent_activity_required: "Necesitas actividad reciente.",
};

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function normalizeRanking(value: unknown): RankingPayload {
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
    pagination: record(root.pagination) as RankingPayload["pagination"],
    publication: record(root.publication) as RankingPayload["publication"],
    reason: typeof root.reason === "string" ? root.reason : undefined,
    season: record(root.season) as RankingPayload["season"],
    territory: record(root.territory) as RankingPayload["territory"],
  };
}

function normalizeOwnRank(value: unknown): OwnRank {
  const root = record(value) ?? {};
  return {
    available: Boolean(root.available),
    displayName: typeof root.displayName === "string" ? root.displayName : undefined,
    eligibilityState: typeof root.eligibilityState === "string" ? root.eligibilityState : undefined,
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

function statusText(state?: string) {
  if (state === "eligible") return "Clasificado";
  if (state === "pending_integrity_review") return "En revisión";
  if (state === "provisional") return "Provisional";
  return "Sin clasificar";
}

function formatPublishedAt(value?: string) {
  if (!value) return "Sin publicación";
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" })
    .format(new Date(value));
}

export function ProvincialRankingProduct() {
  const [ranking, setRanking] = useState<RankingPayload | null>(null);
  const [ownRank, setOwnRank] = useState<OwnRank | null>(null);
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

  const leader = ranking?.items[0] ?? null;
  const availabilityMessage = reasonLabels[ranking?.reason ?? ""]
    ?? "La clasificación provincial se abrirá cuando el piloto esté listo.";
  const ownMessage = ownRank?.reasonCodes?.map((code) => reasonLabels[code] ?? code).join(" · ")
    || reasonLabels[ownRank?.reason ?? ""];
  const publishedLabel = formatPublishedAt(ranking?.publication?.publishedAt);

  return (
    <main className={styles.shell}>
      <header className={styles.topbar}>
        <div>
          <Link href="/" className={styles.back}>Volver</Link>
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

      <div className={styles.layout}>
        <section className={styles.rankingPanel} aria-busy={loading}>
          <header>
            <div><span>Clasificación oficial</span><h2>Top {ranking?.territory?.provinceName ?? "provincial"}</h2></div>
            <strong>{ranking?.pagination?.total ?? ranking?.items.length ?? 0} jugadores</strong>
          </header>
          {loading && !ranking ? <div className={styles.empty}>Actualizando clasificación...</div>
            : !ranking?.available ? <div className={styles.empty}>{availabilityMessage}</div>
              : <ol className={styles.list}>
                {ranking.items.map((item) => (
                  <li key={item.entryKey} data-podium={item.position <= 3 ? item.position : undefined}>
                    <b>{item.position}</b>
                    <div className={styles.player}>
                      <strong>{item.displayName}</strong>
                      <span>{item.validChallenges} retos · {item.logicalOpponents} rivales</span>
                    </div>
                    <div className={styles.components} aria-label="Componentes del Season Score">
                      <span title="Calidad">CAL {item.components.quality}</span>
                      <span title="Competición">COM {item.components.competition}</span>
                      <span title="Oposición">OPO {item.components.opposition}</span>
                    </div>
                    <output>{item.score}</output>
                  </li>
                ))}
              </ol>}
        </section>

        <aside className={styles.side}>
          <section className={styles.ownPanel}>
            <header><span>Mi posición</span><b data-state={ownRank?.eligibilityState}>{statusText(ownRank?.eligibilityState)}</b></header>
            {ownRank?.available ? <>
              <div className={styles.ownScore}>
                <strong>{ownRank.position ? `#${ownRank.position}` : "--"}</strong>
                <output>{ownRank.score ?? 0}</output>
              </div>
              <h2>{ownRank.displayName}</h2>
              <p>{ownRank.validChallenges} retos válidos · {ownRank.logicalOpponents} rivales</p>
              {ownMessage && <small>{ownMessage}</small>}
            </> : <div className={styles.ownEmpty}>{ownMessage ?? "Inicia sesión para consultar tu posición."}</div>}
          </section>

          <section className={styles.formulaPanel}>
            <span>Season Score V3</span>
            <h2>Una puntuación, tres señales</h2>
            <dl>
              <div><dt>Calidad</dt><dd>55%</dd></div>
              <div><dt>Competición</dt><dd>30%</dd></div>
              <div><dt>Oposición</dt><dd>15%</dd></div>
            </dl>
            {leader && <p>Líder actual: <strong>{leader.displayName}</strong> con {leader.score} puntos.</p>}
          </section>
        </aside>
      </div>
    </main>
  );
}
