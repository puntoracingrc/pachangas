"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import {
  CosmeticCategoryTabs,
  CosmeticEditorShell,
  EditorActions,
  NewBadge,
  OwnedCosmeticSelector,
  UnsavedChanges,
} from "../_components/cosmetics-editor";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import { ProductFeedback, ProductState } from "../_components/product-state";
import { CLIENT_VERSION } from "../client-version-contract";
import { googleAuthEntryHref } from "../google-auth-return";
import { currentClientDisplayMode } from "../pwa-client-bridge";
import {
  EMPTY_PLAYER_COSMETIC_LOADOUT,
  PLAYER_COSMETIC_SLOTS,
  cosmeticKeyForSlot,
  normalizePlayerCosmeticsSnapshot,
  playerCosmeticLoadoutsEqual,
  readPlayerCosmeticsCache,
  unseenCosmeticsBySlot,
  withCosmeticKey,
  writePlayerCosmeticsCache,
  type PlayerCosmeticLoadout,
  type PlayerCosmeticSlot,
  type PlayerCosmeticsSnapshot,
} from "../player-cosmetics-contract";
import { supabase } from "../supabaseClient";
import { SERVICE_UNAVAILABLE_MESSAGE, userFacingError } from "../user-facing-error";
import styles from "./page.module.css";

type EditorCategory = PlayerCosmeticSlot | "badge";

type PlayerCardProfile = {
  avatar: string | null;
  currentFacets: Record<string, number>;
  displayName: string;
  id: string;
  position: string;
  score: number;
  stats: { appearances: number; goals: number };
};

const FACET_LABELS = [
  ["pace", "RIT"],
  ["shooting", "TIR"],
  ["passing", "PAS"],
  ["dribbling", "REG"],
  ["defending", "DEF"],
  ["physical", "FÍS"],
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function playerProfileRequired(value: unknown) {
  return isRecord(value)
    && typeof value.message === "string"
    && /player profile required/i.test(value.message);
}

function profileFromRow(value: unknown): PlayerCardProfile | null {
  if (!isRecord(value) || typeof value.id !== "string") return null;
  const currentFacets = isRecord(value.current_facets)
    ? Object.fromEntries(Object.entries(value.current_facets).map(([key, entry]) => [key, Number(entry) || 50]))
    : {};
  const stats = isRecord(value.stats) ? value.stats : {};
  return {
    avatar: typeof value.avatar === "string" ? value.avatar : null,
    currentFacets,
    displayName: typeof value.display_name === "string" ? value.display_name : "Jugador",
    id: value.id,
    position: typeof value.outfield_position === "string"
      ? value.outfield_position
      : typeof value.position === "string" ? value.position : "Mediocentro / pivote",
    score: Math.round(Number(value.current_overall) || Number(value.rating) * 10 || 50),
    stats: {
      appearances: Math.max(0, Number(stats.appearances) || 0),
      goals: Math.max(0, Number(stats.goals) || 0),
    },
  };
}

function shortPosition(value: string) {
  const normalized = value.toLowerCase();
  if (normalized.includes("portero")) return "POR";
  if (normalized.includes("delanter")) return "DEL";
  if (normalized.includes("banda")) return "MD";
  if (normalized.includes("defensa")) return "DFC";
  if (normalized.includes("pivote")) return "PIV";
  return "MC";
}

function clientMetadata() {
  return {
    clientVersion: CLIENT_VERSION,
    displayMode: currentClientDisplayMode(),
    surface: "player-cosmetics-editor",
  };
}

function operationKey(kind: string, revision: number, value: unknown) {
  return `${kind}:${revision}:${JSON.stringify(value)}`;
}

export default function PlayerCosmeticsPage() {
  const [activeCategory, setActiveCategory] = useState<EditorCategory>("frame");
  const [busy, setBusy] = useState("");
  const [draft, setDraft] = useState<PlayerCosmeticLoadout>({ ...EMPTY_PLAYER_COSMETIC_LOADOUT });
  const [message, setMessage] = useState(supabase ? "" : SERVICE_UNAVAILABLE_MESSAGE);
  const [missingProfile, setMissingProfile] = useState(false);
  const [profile, setProfile] = useState<PlayerCardProfile | null>(null);
  const [sessionResolved, setSessionResolved] = useState(!supabase);
  const [snapshot, setSnapshot] = useState<PlayerCosmeticsSnapshot | null>(null);
  const [userId, setUserId] = useState("");
  const operationIds = useRef(new Map<string, string>());
  const dirtyRef = useRef(false);
  const deepLinkAppliedProfileRef = useRef("");

  const dirty = Boolean(snapshot && !playerCosmeticLoadoutsEqual(draft, snapshot.loadout));

  useEffect(() => {
    dirtyRef.current = dirty;
  }, [dirty]);

  const acceptSnapshot = useCallback((value: unknown, preserveDraft = dirtyRef.current) => {
    const canonical = normalizePlayerCosmeticsSnapshot(value);
    if (!canonical) return false;
    setSnapshot(canonical);
    if (!preserveDraft) setDraft(canonical.loadout);
    if (userId) {
      try {
        writePlayerCosmeticsCache(window.localStorage, userId, canonical);
      } catch {
        // Derived cache is optional and never authoritative.
      }
    }
    return true;
  }, [userId]);

  const loadSnapshot = useCallback(async (preserveDraft = dirtyRef.current) => {
    if (!supabase) return;
    const result = await supabase.rpc("get_pachanga_player_cosmetics_snapshot_v1");
    if (result.error) {
      if (playerProfileRequired(result.error)) {
        setMissingProfile(true);
        setMessage("");
        return;
      }
      setMissingProfile(false);
      setMessage(userFacingError(result.error, "No pudimos recuperar tu colección. Vuelve a intentarlo."));
      return;
    }
    setMissingProfile(false);
    if (!acceptSnapshot(result.data, preserveDraft)) setMessage("El servidor devolvió una colección no válida.");
  }, [acceptSnapshot]);

  useEffect(() => {
    if (!supabase) return;
    const client = supabase;
    let active = true;
    void client.auth.getSession().then(({ data }) => {
      const user = data.session?.user ?? null;
      if (!active) return;
      if (!user) {
        setMessage("Inicia sesión para personalizar tu ficha.");
        setSessionResolved(true);
        return;
      }
      setMessage("");
      setUserId(user.id);
      setSessionResolved(true);
      try {
        const cached = readPlayerCosmeticsCache(window.localStorage, user.id);
        if (cached) {
          setSnapshot(cached);
          setDraft(cached.loadout);
        }
      } catch {
        // Cache misses are expected on a new device.
      }
    });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!supabase || !userId) return;
    const client = supabase;
    let active = true;
    void (async () => {
      const profileResult = await client
        .from("pachanga_player_profiles")
        .select("id, display_name, avatar, position, outfield_position, rating, current_overall, current_facets, stats")
        .eq("user_id", userId)
        .maybeSingle();
      if (!active) return;
      if (profileResult.error) {
        setMessage(userFacingError(profileResult.error, "No pudimos recuperar tu ficha. Vuelve a intentarlo."));
      }
      else setProfile(profileFromRow(profileResult.data));
      await loadSnapshot(false);
    })();
    return () => {
      active = false;
    };
  }, [loadSnapshot, userId]);

  useEffect(() => {
    if (!snapshot || deepLinkAppliedProfileRef.current === snapshot.playerProfileId) return;
    const query = new URLSearchParams(window.location.search);
    const requestedSlot = query.get("slot");
    const requestedItem = query.get("item");
    const validSlot = PLAYER_COSMETIC_SLOTS.find((candidate) => candidate === requestedSlot);
    if (!validSlot) return;
    deepLinkAppliedProfileRef.current = snapshot.playerProfileId;
    queueMicrotask(() => {
      setActiveCategory(validSlot);
      if (requestedItem && snapshot.owned.some((item) => item.slot === validSlot && item.key === requestedItem)) {
        setDraft((current) => withCosmeticKey(current, validSlot, requestedItem));
      }
    });
  }, [snapshot]);

  useEffect(() => {
    if (!supabase || !snapshot?.playerProfileId) return;
    const client = supabase;
    const profileId = snapshot.playerProfileId;
    const channel = client
      .channel(`player-cosmetics-${profileId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "pachanga_player_cosmetic_loadouts", filter: `player_profile_id=eq.${profileId}` }, () => void loadSnapshot())
      .on("postgres_changes", { event: "*", schema: "public", table: "pachanga_player_reward_inventory", filter: `player_profile_id=eq.${profileId}` }, () => void loadSnapshot())
      .subscribe();
    const reconnect = () => {
      if (navigator.onLine) void loadSnapshot();
    };
    window.addEventListener("online", reconnect);
    return () => {
      window.removeEventListener("online", reconnect);
      void client.removeChannel(channel);
    };
  }, [loadSnapshot, snapshot?.playerProfileId]);

  const unseen = useMemo(() => unseenCosmeticsBySlot(snapshot?.owned ?? []), [snapshot?.owned]);
  const counts = { ...unseen, badge: 0 };
  const activeItems = activeCategory === "badge"
    ? []
    : snapshot?.owned.filter((item) => item.slot === activeCategory) ?? [];
  const selectedBadge = snapshot?.featuredBadges.find((entry) => entry.grantId === draft.featuredBadgeGrantId) ?? null;

  async function markCategorySeen(category: EditorCategory) {
    setActiveCategory(category);
    if (!supabase || !snapshot || category === "badge" || busy || !navigator.onLine) return;
    const keys = snapshot.owned.filter((item) => item.slot === category && !item.seenAt).map((item) => item.key);
    if (!keys.length) return;
    const fingerprint = operationKey("seen", snapshot.revision, keys);
    const operationId = operationIds.current.get(fingerprint) ?? crypto.randomUUID();
    operationIds.current.set(fingerprint, operationId);
    setBusy("seen");
    const result = await supabase.rpc("mark_pachanga_player_cosmetics_seen_v1", {
      client_metadata: clientMetadata(),
      expected_revision: snapshot.revision,
      operation_id: operationId,
      target_cosmetic_keys: keys,
    });
    setBusy("");
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") await loadSnapshot();
      return;
    }
    operationIds.current.delete(fingerprint);
    acceptSnapshot(result.data, true);
  }

  async function saveLoadout() {
    if (!supabase || !snapshot || busy || !dirty) return;
    if (!navigator.onLine) {
      setMessage("Sin conexión: la previsualización no se guardó. Reconecta para confirmar el cambio.");
      return;
    }
    const fingerprint = operationKey("save", snapshot.revision, draft);
    const operationId = operationIds.current.get(fingerprint) ?? crypto.randomUUID();
    operationIds.current.set(fingerprint, operationId);
    setBusy("save");
    setMessage("");
    const result = await supabase.rpc("save_pachanga_player_cosmetic_loadout_v1", {
      client_metadata: clientMetadata(),
      expected_revision: snapshot.revision,
      operation_id: operationId,
      target_loadout: draft,
    });
    setBusy("");
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") await loadSnapshot();
      return;
    }
    operationIds.current.delete(fingerprint);
    if (acceptSnapshot(result.data, false)) setMessage("Ficha confirmada por el servidor.");
  }

  const facets = FACET_LABELS.map(([key, label]) => ({
    key,
    label,
    value: Math.round(profile?.currentFacets[key] ?? 50),
  }));
  const pageState = !supabase
    ? {
        description: SERVICE_UNAVAILABLE_MESSAGE,
        eyebrow: "Servicio no disponible",
        title: "Tu colección sigue a salvo",
      }
    : !sessionResolved
      ? {
          description: "Estamos recuperando tu ficha y tu colección confirmada.",
          eyebrow: "Sincronizando",
          title: "Cargando tu ficha",
        }
      : !userId
        ? {
            description: "Entra con tu cuenta para ver las piezas que has conseguido y guardar cambios.",
            eyebrow: "Sesión necesaria",
            title: "Personaliza tu ficha",
          }
        : missingProfile
          ? {
              description: "Crea primero tu ficha de jugador para acceder a tu colección personal.",
              eyebrow: "Ficha pendiente",
              title: "Tu carta aún no está creada",
            }
          : !snapshot && message
          ? {
              description: message,
              eyebrow: "No se pudo cargar",
              title: "Tu colección no está disponible",
            }
          : !snapshot
            ? {
                description: "Estamos recuperando la última revisión confirmada por el servidor.",
                eyebrow: "Sincronizando",
                title: "Cargando tu colección",
              }
            : null;

  return (
    <OfficialProductShellV2
      active="perfil"
      context={{
        detail: dirty ? "Cambios sin guardar" : `${snapshot?.owned.length ?? 0} piezas`,
        eyebrow: "Mi ficha",
        status: snapshot ? `Revisión ${snapshot.revision}` : "Sincronizando",
        title: "Personalizar carta",
      }}
    >
    <main className={styles.page} data-official-surface="player-card">
      <nav className={styles.topbar}>
        <Link href="/?mobile=perfil">Volver</Link>
        <strong>Mi ficha</strong>
        <UnsavedChanges dirty={dirty} />
      </nav>

      <header className={styles.header}>
        <div>
          <span>Colección personal</span>
          <h1>Personalizar ficha</h1>
        </div>
        <div className={styles.headerStats}>
          <span>{snapshot?.owned.length ?? 0} piezas</span>
          <span>Revisión {snapshot?.revision ?? 0}</span>
        </div>
      </header>

      {pageState ? (
        <ProductState
          actions={sessionResolved && !userId
            ? (
                <Link
                  href={googleAuthEntryHref("/personalizar-carta")}
                  onClick={(event) => {
                    event.preventDefault();
                    window.location.assign(googleAuthEntryHref(`${window.location.pathname}${window.location.search}`));
                  }}
                >
                  Iniciar sesión
                </Link>
              )
            : missingProfile ? <Link href="/?mobile=perfil">Crear mi ficha</Link> : undefined}
          busy={!sessionResolved || Boolean(userId && !snapshot && !message && !missingProfile)}
          description={pageState.description}
          eyebrow={pageState.eyebrow}
          surface="dark"
          title={pageState.title}
        />
      ) : snapshot ? (
        <>
          {!snapshot.enabled ? (
            <p className={styles.notice}>La colección está preparada, pero todavía no se ha activado para este entorno.</p>
          ) : null}

          <CosmeticEditorShell
        actions={(
          <EditorActions
            busy={Boolean(busy)}
            onPrimary={() => void saveLoadout()}
            onReset={() => setDraft(snapshot?.loadout ?? EMPTY_PLAYER_COSMETIC_LOADOUT)}
            primaryDisabled={!dirty || !snapshot?.enabled}
            primaryLabel={busy === "save" ? "Guardando..." : "Guardar ficha"}
          />
        )}
        preview={(
          <PlayerCosmeticCard
            ariaLabel={`Ficha de ${profile?.displayName ?? "Jugador"}`}
            className="fifa-card-gold readonly-card"
            cosmetics={snapshot?.owned}
            facets={facets}
            featuredAchievement={selectedBadge}
            loadout={draft}
            meta={`${profile?.stats.goals ?? 0} Goles · ${profile?.stats.appearances ?? 0} PJ`}
            name={profile?.displayName ?? "Jugador"}
            photoAlt={`Foto de ${profile?.displayName ?? "Jugador"}`}
            photoSrc={profile?.avatar}
            position={shortPosition(profile?.position ?? "")}
            score={profile?.score ?? 50}
          />
        )}
      >
        <CosmeticCategoryTabs active={activeCategory} counts={counts} onChange={(category) => void markCategorySeen(category)} />
        <div className={styles.categoryHeading}>
          <div>
            <span>{activeCategory === "badge" ? "Logro destacado" : "Piezas propias"}</span>
            <strong>{activeCategory === "badge" ? "Solo logros conseguidos" : `${activeItems.length} disponibles`}</strong>
          </div>
          {activeCategory !== "badge" && unseen[activeCategory] ? <NewBadge count={unseen[activeCategory]} /> : null}
        </div>
        {activeCategory === "badge" ? (
          <div className={styles.badgeGrid}>
            <button className={!draft.featuredBadgeGrantId ? styles.selectedBadge : ""} type="button" onClick={() => setDraft((current) => ({ ...current, featuredBadgeGrantId: null }))}>
              <span aria-hidden="true">☆</span><strong>Sin logro destacado</strong>
            </button>
            {(snapshot?.featuredBadges ?? []).map((entry) => (
              <button className={draft.featuredBadgeGrantId === entry.grantId ? styles.selectedBadge : ""} key={entry.grantId} type="button" onClick={() => setDraft((current) => ({ ...current, featuredBadgeGrantId: entry.grantId }))}>
                <span aria-hidden="true">★</span><strong>{entry.title}</strong><small>{entry.rarity}</small>
              </button>
            ))}
          </div>
        ) : (
          <OwnedCosmeticSelector
            items={activeItems}
            noneLabel={activeCategory === "effect" || activeCategory === "title" ? "Ninguno" : "Original"}
            onChange={(key) => setDraft((current) => withCosmeticKey(current, activeCategory, key))}
            selectedKey={cosmeticKeyForSlot(draft, activeCategory)}
          />
        )}
          </CosmeticEditorShell>
        </>
      ) : null}

      {snapshot && message ? (
        <ProductFeedback tone={message.includes("confirmada") ? "success" : "error"}>{message}</ProductFeedback>
      ) : null}
    </main>
    </OfficialProductShellV2>
  );
}
