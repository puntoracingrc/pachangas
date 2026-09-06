"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { useCallback, useEffect, useRef, useState } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { TeamShieldCosmeticsEditor, teamShieldItemsForSlot } from "../team-shield-editor";
import { ProductFeedback, ProductState } from "../../_components/product-state";
import { TeamShieldView } from "../../_components/team-shield-view";
import { CLIENT_VERSION } from "../../client-version-contract";
import { googleAuthEntryHref } from "../../google-auth-return";
import {
  normalizePlayerCosmeticsSnapshot,
  type PlayerCosmeticsSnapshot,
} from "../../player-cosmetics-contract";
import { currentClientDisplayMode } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import {
  teamShieldDesignEquals,
  type TeamShieldConfig,
  type TeamShieldCosmeticSlot,
} from "../../team-shield-contract";
import {
  normalizePendingReward,
  normalizeProgressionSnapshot,
  normalizeTeamShieldSnapshot,
  opensPendingRewardSequence,
  readTeamIdentityCache,
  writeTeamIdentityCache,
  type CrestCatalogItem,
  type PendingReward,
  type ProgressionAchievement,
  type ProgressionSnapshot,
  type TeamShieldSnapshot,
} from "../../team-identity-contract";
import styles from "./page.module.css";
import { SERVICE_UNAVAILABLE_MESSAGE, userFacingError } from "../../user-facing-error";

const RewardBoxDemo = dynamic(
  () => import("../../reward-box-demo").then((module) => module.RewardBoxDemo),
  { ssr: false },
);

type Membership = {
  groupId: string;
  name: string;
  role: "admin" | "owner" | "player";
};


const familyLabels: Partial<Record<CrestCatalogItem["family"], string>> = {
  adornment: "Adorno",
  border: "Borde",
  effect: "Efecto",
  palette: "Paleta especial",
  pattern: "Patrón",
  shape: "Forma",
  symbol: "Símbolo",
};

function clientMetadata() {
  return {
    clientVersion: CLIENT_VERSION,
    displayMode: currentClientDisplayMode(),
    surface: "team-identity",
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function membershipsFromRows(value: unknown): Membership[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((row) => {
    if (!isRecord(row)) return [];
    const group = Array.isArray(row.pachanga_groups) ? row.pachanga_groups[0] : row.pachanga_groups;
    if (!isRecord(group) || typeof row.group_id !== "string" || typeof group.name !== "string") return [];
    return [{
      groupId: row.group_id,
      name: group.name,
      role: row.role === "owner" || row.role === "admin" ? row.role : "player",
    }];
  });
}

function dateLabel(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" }).format(parsed);
}

function rewardResultLabel(reward: PendingReward) {
  const payload = reward.rewardPayload;
  const grant = payload && isRecord(payload.grant) ? payload.grant : null;
  if (!grant) return "Premio confirmado por el servidor";
  const points = Math.max(0, Math.floor(Number(grant.pointsGranted) || 0));
  const cosmeticKey = typeof grant.cosmeticKey === "string" ? grant.cosmeticKey : "";
  const duplicate = grant.duplicateConverted === true;
  if (duplicate && cosmeticKey) return `${cosmeticKey} repetido · convertido en ${points} puntos`;
  if (cosmeticKey && points) return `${cosmeticKey} + ${points} puntos`;
  if (cosmeticKey) return cosmeticKey;
  return `${points} puntos`;
}

function grantedPlayerCosmetic(reward: PendingReward | null) {
  const payload = reward?.rewardPayload;
  const grant = payload && isRecord(payload.grant) ? payload.grant : null;
  if (!grant || grant.cosmeticGranted !== true || typeof grant.cosmeticKey !== "string") return null;
  return grant.cosmeticKey;
}

export default function TeamIdentityPage() {
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [userId, setUserId] = useState("");
  const [crest, setCrest] = useState<TeamShieldSnapshot | null>(null);
  const [progression, setProgression] = useState<ProgressionSnapshot | null>(null);
  const [draftDesign, setDraftDesign] = useState<TeamShieldConfig | null>(null);
  const [confirmedDesign, setConfirmedDesign] = useState<TeamShieldConfig | null>(null);
  const [activeShieldCategory, setActiveShieldCategory] = useState<TeamShieldCosmeticSlot>("shape");
  const [isOnline, setIsOnline] = useState(true);
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState(supabase ? "" : SERVICE_UNAVAILABLE_MESSAGE);
  const [membershipStatus, setMembershipStatus] = useState<"error" | "loading" | "no-team" | "ready" | "signed-out" | "unavailable">(
    supabase ? "loading" : "unavailable",
  );
  const [rewardSequence, setRewardSequence] = useState<PendingReward[]>([]);
  const [rewardSequenceIndex, setRewardSequenceIndex] = useState(0);
  const [openedReward, setOpenedReward] = useState<PendingReward | null>(null);
  const [playerCosmetics, setPlayerCosmetics] = useState<PlayerCosmeticsSnapshot | null>(null);
  const [sequenceRecognitions, setSequenceRecognitions] = useState<ProgressionAchievement[]>([]);
  const operationIds = useRef(new Map<string, string>());
  const handledRewardDeepLinks = useRef(new Set<string>());
  const handledTeamCosmeticDeepLinks = useRef(new Set<string>());
  const handledAchievementNavigation = useRef("");
  useEffect(() => {
    if (!progression || progression.groupId !== selectedGroupId || window.location.hash !== "#logros" || handledAchievementNavigation.current === selectedGroupId) return;
    const frame = window.requestAnimationFrame(() => {
      const section = document.getElementById("logros");
      if (section) {
        section.scrollIntoView({ block: "start" });
        handledAchievementNavigation.current = selectedGroupId;
      }
    });
    return () => window.cancelAnimationFrame(frame);
  }, [progression, selectedGroupId]);

  const loadPlayerCosmetics = useCallback(async () => {
    if (!supabase || !userId) return;
    const result = await supabase.rpc("get_pachanga_player_cosmetics_snapshot_v1");
    if (result.error) return;
    const canonical = normalizePlayerCosmeticsSnapshot(result.data);
    if (canonical) setPlayerCosmetics(canonical);
  }, [userId]);

  const persistCache = useCallback((nextShield: TeamShieldSnapshot | null, nextProgression: ProgressionSnapshot | null) => {
    if (!userId || !selectedGroupId) return;
    try {
      writeTeamIdentityCache(window.localStorage, userId, selectedGroupId, nextShield, nextProgression);
    } catch {
      // Cache is derived and optional.
    }
  }, [selectedGroupId, userId]);

  const loadCrest = useCallback(async () => {
    if (!supabase || !selectedGroupId) return;
    const result = await supabase.rpc("get_pachanga_team_shield_snapshot_v1", { target_group_id: selectedGroupId });
    if (result.error) {
      setMessage(userFacingError(result.error, "No pudimos recuperar el escudo del equipo."));
      return;
    }
    const canonical = normalizeTeamShieldSnapshot(result.data);
    if (!canonical || canonical.group.groupId !== selectedGroupId) {
      setMessage("El servidor devolvió un escudo no válido.");
      return;
    }
    setCrest(canonical);
    setProgression((current) => {
      persistCache(canonical, current);
      return current;
    });
  }, [persistCache, selectedGroupId]);

  const loadProgression = useCallback(async () => {
    if (!supabase || !selectedGroupId) return;
    const result = await supabase.rpc("get_pachanga_progression_snapshot_v1", { target_group_id: selectedGroupId });
    if (result.error) {
      setMessage(userFacingError(result.error, "No pudimos recuperar la progresión del equipo."));
      return;
    }
    const canonical = normalizeProgressionSnapshot(result.data);
    if (!canonical || canonical.groupId !== selectedGroupId) {
      setMessage("El servidor devolvió una progresión no válida.");
      return;
    }
    setProgression(canonical);
    if (
      opensPendingRewardSequence(window.location.search)
      && !handledRewardDeepLinks.current.has(canonical.groupId)
    ) {
      handledRewardDeepLinks.current.add(canonical.groupId);
      const pending = canonical.rewards.filter((reward) => reward.status === "pending");
      if (pending.length) {
        setRewardSequence(pending);
        setRewardSequenceIndex(0);
        setOpenedReward(null);
        setSequenceRecognitions([]);
      }
    }
    setCrest((current) => {
      persistCache(current, canonical);
      return current;
    });
  }, [persistCache, selectedGroupId]);

  useEffect(() => {
    if (!supabase) return;
    const client = supabase;
    let active = true;
    void client.auth.getSession().then(async ({ data }) => {
      const user = data.session?.user ?? null;
      if (!active) return;
      if (!user) {
        setMessage("Inicia sesión para ver la identidad de tu equipo.");
        setMembershipStatus("signed-out");
        return;
      }
      setUserId(user.id);
      const result = await client
        .from("pachanga_group_members")
        .select("group_id, role, pachanga_groups(id, name)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: true });
      if (!active) return;
      if (result.error) {
        setMessage(userFacingError(result.error, "No pudimos recuperar tus equipos."));
        setMembershipStatus("error");
        return;
      }
      const groups = membershipsFromRows(result.data);
      setMemberships(groups);
      setMessage("");
      setMembershipStatus(groups.length ? "ready" : "no-team");
      const queryGroupId = new URLSearchParams(window.location.search).get("grupo") ?? "";
      const cachedGroupId = window.localStorage.getItem("pachangas-identity-selected-group") ?? "";
      const preferred = groups.find((group) => group.groupId === queryGroupId)?.groupId
        ?? groups.find((group) => group.groupId === cachedGroupId)?.groupId
        ?? groups[0]?.groupId
        ?? "";
      setSelectedGroupId(preferred);
    });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!selectedGroupId || !userId) return;
    window.localStorage.setItem("pachangas-identity-selected-group", selectedGroupId);
    const cached = readTeamIdentityCache(window.localStorage, userId, selectedGroupId);
    queueMicrotask(() => {
      setCrest(cached?.shield ?? null);
      setProgression(cached?.progression ?? null);
      setDraftDesign(null);
      setConfirmedDesign(null);
      setMessage("");
    });
    queueMicrotask(() => void Promise.all([loadCrest(), loadProgression()]));
  }, [loadCrest, loadProgression, selectedGroupId, userId]);

  useEffect(() => {
    if (!userId) return;
    queueMicrotask(() => void loadPlayerCosmetics());
  }, [loadPlayerCosmetics, userId]);

  useEffect(() => {
    if (!crest) return;
    const nextConfirmed = crest.config;
    queueMicrotask(() => {
      setDraftDesign((current) => (
        !current || !confirmedDesign || teamShieldDesignEquals(current, confirmedDesign)
          ? nextConfirmed
          : current
      ));
      setConfirmedDesign(nextConfirmed);
    });
  }, [confirmedDesign, crest]);

  useEffect(() => {
    if (!crest?.canManage) return;
    const cosmeticKey = new URLSearchParams(window.location.search).get("cosmetic") ?? "";
    const item = crest.catalog.find((candidate) => (
      candidate.key === cosmeticKey && candidate.unlocked && candidate.slot
    ));
    if (!item?.slot) return;
    const fingerprint = `${crest.group.groupId}:${item.key}`;
    if (handledTeamCosmeticDeepLinks.current.has(fingerprint)) return;
    handledTeamCosmeticDeepLinks.current.add(fingerprint);
    setActiveShieldCategory(item.slot);
  }, [crest]);

  useEffect(() => {
    const syncOnlineState = () => setIsOnline(navigator.onLine);
    syncOnlineState();
    window.addEventListener("online", syncOnlineState);
    window.addEventListener("offline", syncOnlineState);
    return () => {
      window.removeEventListener("online", syncOnlineState);
      window.removeEventListener("offline", syncOnlineState);
    };
  }, []);

  useEffect(() => {
    if (!supabase || !selectedGroupId || !userId) return;
    const client = supabase;
    const crestChannel = client
      .channel(`pachanga-crest-${selectedGroupId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_shield_state", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadCrest(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_cosmetic_inventory", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadCrest(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_cosmetic_seen", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadCrest(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_shield_loadouts", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadCrest(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_shield_public", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadCrest(),
      )
      .subscribe();
    const progressionChannel = client
      .channel(`pachanga-progression-${selectedGroupId}-${userId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_progression_group_state", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadProgression(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_progression_user_state", filter: `user_id=eq.${userId}` },
        () => void loadProgression(),
      )
      .subscribe();
    const reconnect = () => {
      if (navigator.onLine) void Promise.all([loadCrest(), loadProgression()]);
    };
    window.addEventListener("online", reconnect);
    return () => {
      window.removeEventListener("online", reconnect);
      void client.removeChannel(crestChannel);
      void client.removeChannel(progressionChannel);
    };
  }, [loadCrest, loadProgression, selectedGroupId, userId]);

  useEffect(() => {
    const openRewardDeepLink = () => {
      if (!selectedGroupId || !opensPendingRewardSequence(window.location.search)) return;
      handledRewardDeepLinks.current.delete(selectedGroupId);
      void loadProgression();
    };
    window.addEventListener("pachangas:reward-deep-link", openRewardDeepLink);
    return () => window.removeEventListener("pachangas:reward-deep-link", openRewardDeepLink);
  }, [loadProgression, selectedGroupId]);

  useEffect(() => {
    const dirty = Boolean(
      crest?.teamCosmeticsEnabled
      && draftDesign
      && confirmedDesign
      && !teamShieldDesignEquals(draftDesign, confirmedDesign),
    );
    if (!dirty) return;
    const warnBeforeLeaving = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warnBeforeLeaving);
    return () => window.removeEventListener("beforeunload", warnBeforeLeaving);
  }, [confirmedDesign, crest?.teamCosmeticsEnabled, draftDesign]);

  function operationIdFor(fingerprint: string) {
    const existing = operationIds.current.get(fingerprint);
    if (existing) return existing;
    const created = crypto.randomUUID();
    operationIds.current.set(fingerprint, created);
    return created;
  }

  function acceptCrestCommit(value: unknown) {
    const canonical = normalizeTeamShieldSnapshot(value);
    if (!canonical || canonical.group.groupId !== selectedGroupId) return false;
    setCrest(canonical);
    persistCache(canonical, progression);
    return true;
  }

  async function saveTeamShield() {
    if (!supabase || !crest?.canManage || !crest.teamCosmeticsEnabled || !draftDesign || busy) return;
    if (!navigator.onLine) {
      setMessage("Sin conexión: el diseño queda como borrador local y no se ha guardado.");
      return;
    }
    const fingerprint = `team-shield-save:${selectedGroupId}:${crest.revision}:${JSON.stringify(draftDesign)}`;
    const operationId = operationIdFor(fingerprint);
    setBusy("team-shield-save");
    setMessage("");
    const result = await supabase.rpc("save_pachanga_team_shield_loadout_v1", {
      client_metadata: clientMetadata(),
      expected_revision: crest.revision,
      operation_id: operationId,
      target_config: draftDesign,
      target_group_id: selectedGroupId,
    });
    setBusy("");
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") {
        setDraftDesign(null);
        setConfirmedDesign(null);
        await loadCrest();
      }
      return;
    }
    operationIds.current.delete(fingerprint);
    if (!acceptCrestCommit(result.data)) await loadCrest();
    setMessage("Escudo confirmado y publicado por el servidor.");
  }

  async function markTeamCosmeticsSeen(slot: TeamShieldCosmeticSlot) {
    setActiveShieldCategory(slot);
    if (!supabase || !crest?.canManage || !crest.teamCosmeticsEnabled || busy || !navigator.onLine) return;
    const unseenKeys = teamShieldItemsForSlot(crest.catalog, slot)
      .filter((item) => item.acquiredAt && !item.seenAt)
      .map((item) => item.key);
    if (!unseenKeys.length) return;
    const fingerprint = `team-shield-seen:${selectedGroupId}:${crest.seenRevision}:${unseenKeys.join(",")}`;
    const operationId = operationIdFor(fingerprint);
    setBusy("team-shield-seen");
    const result = await supabase.rpc("mark_pachanga_team_cosmetics_seen_v1", {
      client_metadata: clientMetadata(),
      expected_revision: crest.seenRevision,
      operation_id: operationId,
      target_cosmetic_keys: unseenKeys,
      target_group_id: selectedGroupId,
    });
    setBusy("");
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") await loadCrest();
      return;
    }
    operationIds.current.delete(fingerprint);
    if (!acceptCrestCommit(result.data)) await loadCrest();
  }

  async function openReward(reward: PendingReward) {
    if (!supabase || busy || reward.status !== "pending") return;
    const fingerprint = `reward-open:${reward.boxId}:${reward.recipientRevision}`;
    const operationId = operationIdFor(fingerprint);
    setBusy(reward.boxId);
    setMessage("");
    const result = await supabase.rpc("open_pachanga_reward_box_v2", {
      client_metadata: clientMetadata(),
      expected_revision: reward.recipientRevision,
      operation_id: operationId,
      target_box_id: reward.boxId,
    });
    setBusy("");
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") await loadProgression();
      return;
    }
    operationIds.current.delete(fingerprint);
    const opened = normalizePendingReward(result.data);
    if (opened) {
      setOpenedReward(opened);
      setRewardSequence((sequence) => sequence.map((entry) => entry.boxId === opened.boxId ? { ...entry, status: "opened" } : entry));
    }
    await Promise.all([loadProgression(), loadPlayerCosmetics()]);
  }

  async function equipOpenedPlayerCosmetic() {
    const cosmeticKey = grantedPlayerCosmetic(openedReward);
    if (!supabase || !openedReward || !cosmeticKey || !playerCosmetics || busy) return;
    const fingerprint = `player-cosmetic-equip:${openedReward.boxId}:${cosmeticKey}:${playerCosmetics.revision}`;
    const operationId = operationIdFor(fingerprint);
    setBusy("equip-player-cosmetic");
    setMessage("");
    const result = await supabase.rpc("equip_pachanga_player_cosmetic_from_box_v1", {
      client_metadata: clientMetadata(),
      expected_revision: playerCosmetics.revision,
      operation_id: operationId,
      target_box_id: openedReward.boxId,
      target_cosmetic_key: cosmeticKey,
    });
    setBusy("");
    if (result.error) {
      setMessage(userFacingError(result.error));
      if (result.error.code === "PT409") await loadPlayerCosmetics();
      return;
    }
    operationIds.current.delete(fingerprint);
    const canonical = normalizePlayerCosmeticsSnapshot(result.data);
    if (canonical) setPlayerCosmetics(canonical);
    setMessage("Cosmético equipado y confirmado por el servidor.");
    advanceRewardSequence();
  }

  function beginRewardSequence(rewards: PendingReward[]) {
    if (!rewards.length) return;
    setRewardSequence(rewards);
    setRewardSequenceIndex(0);
    setOpenedReward(null);
    setSequenceRecognitions([]);
  }

  function closeRewardSequence() {
    setRewardSequence([]);
    setRewardSequenceIndex(0);
    setOpenedReward(null);
  }

  function advanceRewardSequence() {
    const nextIndex = rewardSequence.findIndex((reward) => reward.status === "pending" && reward.boxId !== rewardSequence[rewardSequenceIndex]?.boxId);
    if (nextIndex >= 0) {
      setRewardSequenceIndex(nextIndex);
      setOpenedReward(null);
      return;
    }
    const matchIds = new Set(rewardSequence.map((reward) => reward.matchFactId));
    setSequenceRecognitions(
      (progression?.personalAchievements ?? []).filter(
        (achievement) => achievement.state === "active" && matchIds.has(achievement.matchFactId),
      ),
    );
    closeRewardSequence();
  }

  const teamDesignIsDirty = Boolean(
    crest?.teamCosmeticsEnabled
    && draftDesign
    && confirmedDesign
    && !teamShieldDesignEquals(draftDesign, confirmedDesign),
  );
  const pendingRewards = progression?.rewards.filter((reward) => reward.status === "pending") ?? [];
  const openedRewards = progression?.rewards.filter((reward) => reward.status === "opened") ?? [];
  const rewardEconomy = progression?.rewardEconomy ?? null;
  const currentSequenceReward = rewardSequence[rewardSequenceIndex] ?? null;
  const sequencePending = rewardSequence.filter((reward) => reward.status === "pending");
  const openedCosmeticKey = grantedPlayerCosmetic(openedReward);
  const membershipState = membershipStatus === "unavailable"
    ? {
        description: SERVICE_UNAVAILABLE_MESSAGE,
        eyebrow: "Servicio no disponible",
        title: "La identidad del equipo sigue a salvo",
      }
    : membershipStatus === "loading"
      ? {
          description: "Estamos recuperando tus equipos y la última revisión confirmada.",
          eyebrow: "Sincronizando",
          title: "Cargando identidad",
        }
      : membershipStatus === "signed-out"
        ? {
            description: "Entra con tu cuenta para ver el escudo, la colección y la progresión de tu equipo.",
            eyebrow: "Sesión necesaria",
            title: "Identidad del equipo",
          }
        : membershipStatus === "no-team"
          ? {
              description: "Cuando formes parte de un equipo, aquí aparecerán su escudo, logros, estadísticas y colección.",
              eyebrow: "Sin equipo",
              title: "Aún no perteneces a un equipo",
            }
          : membershipStatus === "error"
            ? {
                description: message || "No pudimos recuperar tus equipos. Vuelve a intentarlo.",
                eyebrow: "No se pudo cargar",
                title: "Identidad no disponible",
              }
            : null;

  return (
    <OfficialProductShellV2
      active="equipo"
      context={{
        detail: memberships.find((membership) => membership.groupId === selectedGroupId)?.role ?? "Equipo",
        eyebrow: "Identidad y progresión",
        status: crest ? `Revisión ${crest.revision}` : "Sincronizando",
        title: crest?.group.name ?? "Pachangas IQ",
      }}
    >
    <main className={styles.page} data-official-surface="team-identity">
      <nav className={styles.topbar}>
        <Link href="/">Inicio</Link>
        <strong>Identidad del equipo</strong>
        <Link href="/mercado?section=retos">Rivales</Link>
      </nav>

      <header className={styles.header}>
        <div>
          <span>Equipo y colección</span>
          <h1>{crest?.group.name ?? "Pachangas IQ"}</h1>
        </div>
        {memberships.length > 1 ? (
          <label>
            Grupo
            <select value={selectedGroupId} onChange={(event) => setSelectedGroupId(event.target.value)}>
              {memberships.map((membership) => <option key={membership.groupId} value={membership.groupId}>{membership.name}</option>)}
            </select>
          </label>
        ) : null}
      </header>

      {membershipState ? (
        <ProductState
          actions={membershipStatus === "no-team"
            ? <><Link href="/">Ir a Inicio</Link><Link href="/mercado?section=equipos">Explorar equipos</Link></>
            : membershipStatus === "signed-out"
              ? <Link href={googleAuthEntryHref("/equipo/identidad")}>Iniciar sesión</Link>
              : undefined}
          busy={membershipStatus === "loading"}
          description={membershipState.description}
          eyebrow={membershipState.eyebrow}
          surface="dark"
          title={membershipState.title}
        />
      ) : null}
      {crest && draftDesign ? (
        <>
          {crest.canManage && crest.teamCosmeticsEnabled ? (
            <TeamShieldCosmeticsEditor
              activeCategory={activeShieldCategory}
              canSave={crest.canManage}
              busy={Boolean(busy)}
              catalog={crest.catalog}
              config={draftDesign}
              dirty={teamDesignIsDirty}
              isOnline={isOnline}
              onCategoryChange={(slot) => void markTeamCosmeticsSeen(slot)}
              onChange={setDraftDesign}
              onReset={() => setDraftDesign(confirmedDesign)}
              onSave={() => void saveTeamShield()}
              revision={crest.revision}
            />
          ) : <section className={styles.crestBand}>
            <div className={styles.previewStage}>
              <TeamShieldView catalog={crest.catalog} className={styles.identityShield} config={draftDesign} />
              <div>
                <span>Escudo oficial</span>
                <strong>{draftDesign.initials}</strong>
                <small>Revisión confirmada {crest.revision}</small>
              </div>
            </div>
            <div className={styles.memberCrestCopy}>
              <strong>{crest.canManage ? "Personalización en preparación" : "Escudo oficial"}</strong>
              <p>{crest.canManage
                ? "La nueva personalización de escudos todavía no está activada para este entorno."
                : "La colección pertenece al equipo. Solo owner y admins pueden guardar cambios."}</p>
            </div>
          </section>}

          {pendingRewards.length ? (
            <section className={styles.rewardsBand}>
              <header><span>Recompensas pendientes</span><strong>{pendingRewards.length}</strong></header>
              <button
                className={styles.openAllRewards}
                disabled={Boolean(busy)}
                type="button"
                onClick={() => beginRewardSequence(pendingRewards)}
              >
                Abrir {pendingRewards.length === 1 ? "premio" : `${pendingRewards.length} premios`}
              </button>
            </section>
          ) : null}

          {rewardEconomy ? (
            <section className={styles.economyBand}>
              <header><span>Mi inventario</span><strong>{rewardEconomy.account.balance} puntos</strong></header>
              <div className={styles.economySummary}>
                <article><span>Cosméticos</span><strong>{rewardEconomy.inventory.length}</strong></article>
                <article><span>Cajas abiertas</span><strong>{openedRewards.length}</strong></article>
                <article><span>Conseguidos</span><strong>{rewardEconomy.account.lifetimeEarned}</strong></article>
                <article><span>Catálogo activo</span><strong>V{rewardEconomy.boxCatalog[0]?.catalogVersion ?? 1}</strong></article>
              </div>
              {rewardEconomy.inventory.length ? (
                <div className={styles.playerInventory} aria-label="Cosméticos personales">
                  {rewardEconomy.inventory.slice(0, 8).map((item) => (
                    <span key={`${item.kind}:${item.key}`}>{item.key}</span>
                  ))}
                </div>
              ) : <small className={styles.economyEmpty}>Tus cosméticos aparecerán al abrir cajas colectivas.</small>}
            </section>
          ) : null}

          <nav className={styles.progressTabs} aria-label="Consultar trayectoria">
            <Link href={`/equipo/logros?team=${encodeURIComponent(selectedGroupId)}`}>Logros, estadísticas y récords del equipo</Link>
            <Link href="/perfil#trayectoria">Mi trayectoria personal</Link>
          </nav>

          <section className={styles.collectionBand}>
            <header><span>Colección del equipo</span><strong>{crest.catalog.filter((item) => item.unlocked).length}/{crest.catalog.length}</strong></header>
            <div className={styles.collectionGrid}>
              {crest.catalog.map((item) => (
                <article className={item.unlocked ? styles.unlockedItem : styles.lockedItem} key={item.key}>
                  <span>{familyLabels[item.family] ?? item.family}</span>
                  <strong>{item.name}</strong>
                  <small>{item.unlocked ? "Disponible" : "Bloqueado por logro"}</small>
                </article>
              ))}
            </div>
          </section>

          <section className={styles.historyBand}>
            <header><span>Historial publicado</span><strong>{crest.history.length}</strong></header>
            <div className={styles.historyRail}>
              {crest.history.map((version) => (
                <article key={version.id}>
                  <TeamShieldView catalog={crest.catalog} config={version.config} size={82} />
                  <div><strong>Versión {version.version}</strong><small>{dateLabel(version.createdAt)}</small></div>
                </article>
              ))}
              {!crest.history.length ? <p className={styles.empty}>La primera publicación quedará guardada aquí.</p> : null}
            </div>
          </section>
        </>
      ) : null}

      {membershipStatus === "ready" && message ? (
        <ProductFeedback presentation="toast" tone={message.includes("confirmado") || message.includes("equipado") ? "success" : "error"}>
          {message}
        </ProductFeedback>
      ) : null}

      <RewardBoxDemo
        key={currentSequenceReward?.boxId ?? "no-reward"}
        rarity={currentSequenceReward?.boxRarity ?? "common"}
        open={Boolean(currentSequenceReward)}
        onClose={closeRewardSequence}
        eyebrow={currentSequenceReward
          ? `Cofre ${rewardSequenceIndex + 1} de ${rewardSequence.length} · ${currentSequenceReward.rewardComponent?.label ?? currentSequenceReward.boxRarity}`
          : undefined}
        title={currentSequenceReward?.achievement.title}
        description={openedReward
          ? `Premio confirmado: ${rewardResultLabel(openedReward)}`
          : "El contenido permanece sellado hasta que abras esta caja."}
        actionDisabled={Boolean(busy)}
        pendingChests={sequencePending.map((reward) => ({ id: reward.boxId, rarity: reward.boxRarity }))}
        currentChestId={currentSequenceReward?.boxId}
        onSelectChest={(id) => {
          if (busy) return;
          const selectedIndex = rewardSequence.findIndex((reward) => reward.boxId === id && reward.status === "pending");
          if (selectedIndex < 0 || selectedIndex === rewardSequenceIndex) return;
          setRewardSequenceIndex(selectedIndex);
          setOpenedReward(null);
          void openReward(rewardSequence[selectedIndex]);
        }}
        remainingCount={openedReward ? sequencePending.length : undefined}
        continueLabel={openedReward
          ? sequencePending.length > 0 ? "Abrir siguiente cofre →" : "Terminar y ver mis logros"
          : undefined}
        onContinue={openedReward ? () => {
          if (busy) return;
          const nextReward = sequencePending.find((reward) => reward.boxId !== currentSequenceReward?.boxId);
          advanceRewardSequence();
          if (nextReward) void openReward(nextReward);
        } : undefined}
        actionLabel={openedReward
          ? openedCosmeticKey ? busy === "equip-player-cosmetic" ? "Equipando..." : "Equipar ahora" : undefined
          : busy ? "Abriendo..." : "Abrir caja"}
        onAction={() => {
          if (!currentSequenceReward) return;
          if (openedCosmeticKey) void equipOpenedPlayerCosmetic();
          else if (!openedReward) void openReward(currentSequenceReward);
        }}
        secondaryActionLabel={openedCosmeticKey ? "Ver mi colección" : undefined}
        onSecondaryAction={openedCosmeticKey ? () => {
          const item = playerCosmetics?.owned.find((entry) => entry.key === openedCosmeticKey);
          window.location.assign(`/personalizar-carta?slot=${encodeURIComponent(item?.slot ?? "frame")}&item=${encodeURIComponent(openedCosmeticKey)}`);
        } : undefined}
      />

      {sequenceRecognitions.length ? (
        <div className={styles.rewardModalBackdrop} role="presentation">
          <section className={styles.rewardModal} role="dialog" aria-modal="true" aria-label="Logros personales del partido">
            <span>Tus logros personales del partido</span>
            <strong>{sequenceRecognitions.length}</strong>
            <div className={styles.sequenceRecognitions}>
              {sequenceRecognitions.map((achievement) => (
                <p key={achievement.grantId}>{achievement.title}</p>
              ))}
            </div>
            <button type="button" onClick={() => setSequenceRecognitions([])}>Cerrar</button>
          </section>
        </div>
      ) : null}
    </main>
    </OfficialProductShellV2>
  );
}
