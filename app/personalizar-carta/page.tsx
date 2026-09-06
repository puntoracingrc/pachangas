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
  profileVersion: number;
  score: number;
  stats: { appearances: number; goals: number };
};

type SocialAvatarProfile = {
  avatarRef: string | null;
  revision: number;
};

type AvatarDraft = {
  blob: Blob;
  extension: "jpg" | "webp";
  operationId: string;
  previewUrl: string;
};

const PLAYER_AVATAR_BUCKET = "pachanga-player-avatars";
const MAX_AVATAR_SOURCE_BYTES = 12 * 1024 * 1024;

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
    profileVersion: Math.max(0, Math.floor(Number(value.profile_version) || 0)),
    score: Math.round(Number(value.current_overall) || Number(value.rating) * 10 || 50),
    stats: {
      appearances: Math.max(0, Number(stats.appearances) || 0),
      goals: Math.max(0, Number(stats.goals) || 0),
    },
  };
}

function socialAvatarProfile(value: unknown): SocialAvatarProfile | null {
  if (!isRecord(value)) return null;
  const revision = Math.max(0, Math.floor(Number(value.revision) || 0));
  if (!revision) return null;
  return {
    avatarRef: typeof value.avatarRef === "string" ? value.avatarRef : null,
    revision,
  };
}

function loadImage(source: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onerror = () => reject(new Error("No se pudo leer la imagen."));
    image.onload = () => resolve(image);
    image.src = source;
  });
}

function canvasBlob(canvas: HTMLCanvasElement, type: string, quality: number) {
  return new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, type, quality));
}

async function prepareAvatar(file: File): Promise<AvatarDraft> {
  if (!file.type.startsWith("image/")) throw new Error("El archivo elegido no es una imagen.");
  if (file.size > MAX_AVATAR_SOURCE_BYTES) throw new Error("La foto es demasiado grande. Elige una de menos de 12 MB.");

  const sourceUrl = URL.createObjectURL(file);
  try {
    const image = await loadImage(sourceUrl);
    const imageWidth = image.naturalWidth || image.width;
    const imageHeight = image.naturalHeight || image.height;
    const targetAspect = 420 / 540;
    let cropWidth = imageWidth;
    let cropHeight = imageWidth / targetAspect;
    let cropX = 0;
    let cropY = Math.max(0, (imageHeight - cropHeight) * 0.2);

    if (cropHeight > imageHeight) {
      cropHeight = imageHeight;
      cropWidth = imageHeight * targetAspect;
      cropX = Math.max(0, (imageWidth - cropWidth) / 2);
      cropY = 0;
    }

    const canvas = document.createElement("canvas");
    canvas.width = 420;
    canvas.height = 540;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("No se pudo preparar la foto.");
    context.drawImage(image, cropX, cropY, cropWidth, cropHeight, 0, 0, canvas.width, canvas.height);

    const webp = await canvasBlob(canvas, "image/webp", 0.84);
    const blob = webp?.type === "image/webp" ? webp : await canvasBlob(canvas, "image/jpeg", 0.84);
    if (!blob) throw new Error("No se pudo preparar la foto.");
    if (blob.size > 1024 * 1024) throw new Error("No se pudo reducir la foto lo suficiente.");

    return {
      blob,
      extension: blob.type === "image/webp" ? "webp" : "jpg",
      operationId: crypto.randomUUID(),
      previewUrl: URL.createObjectURL(blob),
    };
  } finally {
    URL.revokeObjectURL(sourceUrl);
  }
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
  const [avatarDraft, setAvatarDraft] = useState<AvatarDraft | null>(null);
  const [avatarMessage, setAvatarMessage] = useState("");
  const [busy, setBusy] = useState("");
  const [draft, setDraft] = useState<PlayerCosmeticLoadout>({ ...EMPTY_PLAYER_COSMETIC_LOADOUT });
  const [message, setMessage] = useState(supabase ? "" : SERVICE_UNAVAILABLE_MESSAGE);
  const [missingProfile, setMissingProfile] = useState(false);
  const [photoMenuOpen, setPhotoMenuOpen] = useState(false);
  const [profile, setProfile] = useState<PlayerCardProfile | null>(null);
  const [returnHref, setReturnHref] = useState("/perfil");
  const [sessionResolved, setSessionResolved] = useState(!supabase);
  const [snapshot, setSnapshot] = useState<PlayerCosmeticsSnapshot | null>(null);
  const [socialProfile, setSocialProfile] = useState<SocialAvatarProfile | null>(null);
  const [userId, setUserId] = useState("");
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const operationIds = useRef(new Map<string, string>());
  const dirtyRef = useRef(false);
  const deepLinkAppliedProfileRef = useRef("");

  const dirty = Boolean(snapshot && !playerCosmeticLoadoutsEqual(draft, snapshot.loadout));
  const hasPendingChanges = dirty || Boolean(avatarDraft);

  useEffect(() => {
    dirtyRef.current = dirty;
  }, [dirty]);

  useEffect(() => {
    const requestedReturn = new URLSearchParams(window.location.search).get("returnTo");
    let active = true;
    if (requestedReturn === "/perfil/test-inicial") {
      queueMicrotask(() => {
        if (active) setReturnHref(requestedReturn);
      });
    }
    return () => { active = false; };
  }, []);

  useEffect(() => () => {
    if (avatarDraft?.previewUrl.startsWith("blob:")) URL.revokeObjectURL(avatarDraft.previewUrl);
  }, [avatarDraft?.previewUrl]);

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

  const loadIdentity = useCallback(async () => {
    if (!supabase || !userId) return false;
    const client = supabase;
    const [profileResult, socialResult] = await Promise.all([
      client
        .from("pachanga_player_profiles")
        .select("id, display_name, avatar, position, outfield_position, rating, current_overall, current_facets, stats, profile_version")
        .eq("user_id", userId)
        .maybeSingle(),
      client.rpc("get_my_pachanga_social_profile_v1"),
    ]);
    if (profileResult.error) {
      setMessage(userFacingError(profileResult.error, "No pudimos recuperar tu ficha. Vuelve a intentarlo."));
      return false;
    }
    const canonicalProfile = profileFromRow(profileResult.data);
    setProfile(canonicalProfile);
    if (socialResult.error) {
      setAvatarMessage("No pudimos preparar la edición de tu foto.");
      return Boolean(canonicalProfile);
    }
    setSocialProfile(socialAvatarProfile(socialResult.data));
    return Boolean(canonicalProfile);
  }, [userId]);

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
    let active = true;
    void (async () => {
      if (!active) return;
      await loadIdentity();
      if (!active) return;
      await loadSnapshot(false);
    })();
    return () => {
      active = false;
    };
  }, [loadIdentity, loadSnapshot, userId]);

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
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_social_invalidations_v1", filter: `audience_user_id=eq.${userId}` }, (event) => {
        if (event.new?.entity_type === "profile" || event.new?.entity_type === "rating_profile") void loadIdentity();
      })
      .subscribe((status) => {
        if (status === "SUBSCRIBED") void loadIdentity();
      });
    const reconnect = () => {
      if (navigator.onLine) {
        void loadSnapshot();
        void loadIdentity();
      }
    };
    window.addEventListener("online", reconnect);
    return () => {
      window.removeEventListener("online", reconnect);
      void client.removeChannel(channel);
    };
  }, [loadIdentity, loadSnapshot, snapshot?.playerProfileId, userId]);

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

  async function persistLoadout() {
    if (!supabase || !snapshot || !dirty) return true;
    const fingerprint = operationKey("save", snapshot.revision, draft);
    const operationId = operationIds.current.get(fingerprint) ?? crypto.randomUUID();
    operationIds.current.set(fingerprint, operationId);
    const result = await supabase.rpc("save_pachanga_player_cosmetic_loadout_v1", {
      client_metadata: clientMetadata(),
      expected_revision: snapshot.revision,
      operation_id: operationId,
      target_loadout: draft,
    });
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") await loadSnapshot();
      return false;
    }
    operationIds.current.delete(fingerprint);
    if (!acceptSnapshot(result.data, false)) {
      setMessage("El servidor no devolvió la colección confirmada.");
      return false;
    }
    return true;
  }

  async function selectAvatar(file: File | undefined) {
    if (!file || busy) return;
    setPhotoMenuOpen(false);
    setAvatarMessage("Preparando la foto...");
    try {
      const prepared = await prepareAvatar(file);
      setAvatarDraft(prepared);
      setAvatarMessage("Foto lista. Pulsa Guardar ficha para confirmarla.");
    } catch (error) {
      setAvatarMessage(error instanceof Error ? error.message : "No se pudo preparar la foto.");
    }
  }

  async function persistAvatar() {
    if (!supabase || !avatarDraft) return true;
    if (!userId || !socialProfile || !profile) {
      setAvatarMessage("No pudimos verificar tu perfil para guardar la foto.");
      return false;
    }

    const objectPath = `${userId}/${socialProfile.revision + 1}-${avatarDraft.operationId}.${avatarDraft.extension}`;
    const bucket = supabase.storage.from(PLAYER_AVATAR_BUCKET);
    const upload = await bucket.upload(objectPath, avatarDraft.blob, {
      cacheControl: "31536000",
      contentType: avatarDraft.blob.type,
      upsert: false,
    });
    if (upload.error && !/already exists/i.test(upload.error.message)) {
      setAvatarMessage(userFacingError(upload.error, "No pudimos subir la foto. Vuelve a intentarlo."));
      return false;
    }

    const avatarRef = bucket.getPublicUrl(objectPath).data.publicUrl;
    const result = await supabase.rpc("command_pachanga_social_profile_v1", {
      action: "profile.avatar.confirm",
      client_metadata: { ...clientMetadata(), playerProfileRevision: profile.profileVersion },
      expected_revision: socialProfile.revision,
      operation_id: avatarDraft.operationId,
      payload: { avatarRef },
    });
    if (result.error) {
      await bucket.remove([objectPath]);
      setAvatarMessage(userFacingError(result.error, "El servidor no pudo confirmar la foto."));
      if (result.error.code === "PT409") await loadIdentity();
      return false;
    }

    const canonicalSocialProfile = socialAvatarProfile(result.data);
    if (!canonicalSocialProfile) {
      setAvatarMessage("El servidor no devolvió el perfil confirmado.");
      return false;
    }
    setSocialProfile(canonicalSocialProfile);
    const identityLoaded = await loadIdentity();
    if (!identityLoaded) {
      setAvatarMessage("La foto se confirmó, pero no pudimos releer tu ficha.");
      return false;
    }
    setAvatarDraft(null);
    setAvatarMessage("Foto confirmada por el servidor.");
    return true;
  }

  async function saveChanges() {
    if (!supabase || !snapshot || busy) return;
    if (!hasPendingChanges) {
      window.location.assign(returnHref);
      return;
    }
    if (!navigator.onLine) {
      setMessage("Sin conexión: la previsualización no se guardó. Reconecta para confirmar el cambio.");
      return;
    }

    setBusy("save");
    setMessage("");
    const cosmeticsSaved = await persistLoadout();
    const avatarSaved = cosmeticsSaved ? await persistAvatar() : false;
    setBusy("");
    if (cosmeticsSaved && avatarSaved) window.location.assign(returnHref);
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
        detail: hasPendingChanges ? "Cambios sin guardar" : "",
        eyebrow: "Mi carta",
        title: "Personalizar carta",
      }}
    >
    <main className={styles.page} data-official-surface="player-card">
      <nav className={styles.topbar}>
        <Link href={returnHref}>Volver</Link>
        <strong>Mi carta</strong>
        <UnsavedChanges dirty={hasPendingChanges} />
      </nav>

      <header className={styles.header}>
        <div>
          <span>Colección personal</span>
          <h1>Personalizar carta</h1>
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
            : missingProfile ? <Link href="/perfil/test-inicial">Hacer test inicial y crear mi carta</Link> : undefined}
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
            onPrimary={() => void saveChanges()}
            onReset={() => {
              setDraft(snapshot?.loadout ?? EMPTY_PLAYER_COSMETIC_LOADOUT);
              setAvatarDraft(null);
              setAvatarMessage("");
              setPhotoMenuOpen(false);
            }}
            primaryDisabled={Boolean(dirty && !snapshot?.enabled)}
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
            photoAction={(
              <>
                <input
                  accept="image/*"
                  aria-label="Elegir foto desde un archivo"
                  className={styles.hiddenPhotoInput}
                  ref={fileInputRef}
                  type="file"
                  onChange={(event) => {
                    void selectAvatar(event.currentTarget.files?.[0]);
                    event.currentTarget.value = "";
                  }}
                />
                <input
                  accept="image/*"
                  aria-label="Hacer una foto con la cámara"
                  capture="user"
                  className={styles.hiddenPhotoInput}
                  ref={cameraInputRef}
                  type="file"
                  onChange={(event) => {
                    void selectAvatar(event.currentTarget.files?.[0]);
                    event.currentTarget.value = "";
                  }}
                />
                {photoMenuOpen ? (
                  <div className={styles.photoMenu} role="menu" aria-label="Añadir foto a la ficha">
                    <button role="menuitem" type="button" onClick={() => fileInputRef.current?.click()}>Elegir archivo</button>
                    <button role="menuitem" type="button" onClick={() => cameraInputRef.current?.click()}>Usar cámara</button>
                  </div>
                ) : null}
              </>
            )}
            photoAlt={`Foto de ${profile?.displayName ?? "Jugador"}`}
            photoClassName={styles.editablePhoto}
            photoProps={{
              "aria-expanded": photoMenuOpen,
              "aria-label": avatarDraft || profile?.avatar ? "Cambiar foto de la ficha" : "Añadir foto a la ficha",
              onClick: () => setPhotoMenuOpen((current) => !current),
              onKeyDown: (event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  setPhotoMenuOpen((current) => !current);
                }
              },
              role: "button",
              tabIndex: 0,
            }}
            photoSrc={avatarDraft?.previewUrl ?? profile?.avatar}
            position={shortPosition(profile?.position ?? "")}
            score={profile?.score ?? 50}
          />
        )}
      >
        {snapshot.owned.length || snapshot.featuredBadges.length ? (
          <>
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
          </>
        ) : (
          <div className={styles.emptyCollection}>
            <span>Foto de jugador</span>
            <strong>Toca el + de tu carta</strong>
            <p>Elige una imagen del teléfono o haz una foto con la cámara. Los marcos y efectos aparecerán aquí cuando los consigas.</p>
          </div>
        )}
        {avatarMessage ? <p className={styles.avatarMessage} role="status">{avatarMessage}</p> : null}
          </CosmeticEditorShell>
        </>
      ) : null}

      {snapshot && message ? (
        <ProductFeedback presentation="toast" tone={message.includes("confirmada") ? "success" : "error"}>{message}</ProductFeedback>
      ) : null}
    </main>
    </OfficialProductShellV2>
  );
}
