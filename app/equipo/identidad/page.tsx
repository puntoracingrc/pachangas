"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { type CSSProperties, useCallback, useEffect, useRef, useState } from "react";
import { CLIENT_VERSION } from "../../client-version-contract";
import { currentClientDisplayMode } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import {
  normalizePendingReward,
  normalizeProgressionSnapshot,
  normalizeTeamCrestSnapshot,
  opensPendingRewardSequence,
  readTeamIdentityCache,
  writeTeamIdentityCache,
  type CrestCatalogItem,
  type CrestDesign,
  type PendingReward,
  type ProgressionAchievement,
  type ProgressionSnapshot,
  type TeamCrestSnapshot,
} from "../../team-identity-contract";
import styles from "./page.module.css";

const RewardBoxDemo = dynamic(
  () => import("../../reward-box-demo").then((module) => module.RewardBoxDemo),
  { ssr: false },
);

type Membership = {
  groupId: string;
  name: string;
  role: "admin" | "owner" | "player";
};

type CrestCss = CSSProperties & {
  "--crest-primary": string;
  "--crest-secondary": string;
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

function symbolLabel(key: string | null) {
  if (key === "symbol.ball") return "⚽";
  if (key === "symbol.lightning") return "ϟ";
  if (key === "symbol.crown") return "♛";
  return "";
}

function colorHex(catalog: CrestCatalogItem[], key: string, fallback: string) {
  const item = catalog.find((entry) => entry.key === key);
  return typeof item?.render.hex === "string" ? item.render.hex : fallback;
}

function CrestPreview({ catalog, design, compact = false }: { catalog: CrestCatalogItem[]; compact?: boolean; design: CrestDesign }) {
  const palette = design.paletteKey ? catalog.find((item) => item.key === design.paletteKey) : null;
  const paletteColors = Array.isArray(palette?.render.palette) ? palette.render.palette.filter((value): value is string => typeof value === "string") : [];
  const primary = paletteColors[0] ?? colorHex(catalog, design.primaryColorKey, "#16a34a");
  const secondary = paletteColors[1] ?? colorHex(catalog, design.secondaryColorKey, "#f8fafc");
  const crestStyle: CrestCss = { "--crest-primary": primary, "--crest-secondary": secondary };
  const shape = design.shapeKey.split(".")[1] ?? "classic";
  const pattern = design.patternKey.split(".")[1] ?? "solid";
  const border = design.borderKey.split(".")[1] ?? "standard";
  return (
    <div
      className={`${styles.crestPreview} ${styles[`shape_${shape}`] ?? ""} ${styles[`pattern_${pattern}`] ?? ""} ${styles[`border_${border}`] ?? ""} ${design.effectKey === "effect.glow" ? styles.glow : ""} ${compact ? styles.compactCrest : ""}`.trim()}
      style={crestStyle}
      role="img"
      aria-label={`Escudo ${design.initials}`}
    >
      {design.adornmentKey === "adornment.star" ? <span className={styles.crestTop}>★</span> : null}
      <span className={styles.crestSymbol}>{symbolLabel(design.symbolKey)}</span>
      <strong>{design.initials}</strong>
      {design.adornmentKey === "adornment.ribbon" ? <span className={styles.crestRibbon}>PACHANGAS IQ</span> : null}
    </div>
  );
}

function CatalogOptions({
  catalog,
  design,
  family,
  onChange,
}: {
  catalog: CrestCatalogItem[];
  design: CrestDesign;
  family: Exclude<CrestCatalogItem["family"], "color">;
  onChange: (key: string | null) => void;
}) {
  const keyForFamily: Record<Exclude<CrestCatalogItem["family"], "color">, keyof CrestDesign> = {
    adornment: "adornmentKey",
    border: "borderKey",
    effect: "effectKey",
    palette: "paletteKey",
    pattern: "patternKey",
    shape: "shapeKey",
    symbol: "symbolKey",
  };
  const selectedKey = design[keyForFamily[family]];
  const optional = family === "adornment" || family === "effect" || family === "palette" || family === "symbol";
  return (
    <fieldset className={styles.optionFieldset}>
      <legend>{familyLabels[family]}</legend>
      <div className={styles.optionGrid}>
        {optional ? (
          <button className={selectedKey === null ? styles.selectedOption : ""} type="button" onClick={() => onChange(null)}>Ninguno</button>
        ) : null}
        {catalog.filter((item) => item.family === family).map((item) => (
          <button
            className={selectedKey === item.key ? styles.selectedOption : ""}
            disabled={!item.unlocked}
            key={item.key}
            type="button"
            onClick={() => onChange(item.key)}
            title={item.unlocked ? item.description : `${item.description} · Bloqueado`}
          >
            <span>{item.name}</span>
            {!item.unlocked ? <small>Bloqueado</small> : null}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

export default function TeamIdentityPage() {
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [userId, setUserId] = useState("");
  const [crest, setCrest] = useState<TeamCrestSnapshot | null>(null);
  const [progression, setProgression] = useState<ProgressionSnapshot | null>(null);
  const [draftDesign, setDraftDesign] = useState<CrestDesign | null>(null);
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState(supabase ? "" : "Supabase no está configurado.");
  const [rewardSequence, setRewardSequence] = useState<PendingReward[]>([]);
  const [rewardSequenceIndex, setRewardSequenceIndex] = useState(0);
  const [openedReward, setOpenedReward] = useState<PendingReward | null>(null);
  const [sequenceRecognitions, setSequenceRecognitions] = useState<ProgressionAchievement[]>([]);
  const operationIds = useRef(new Map<string, string>());
  const handledRewardDeepLinks = useRef(new Set<string>());

  const persistCache = useCallback((nextCrest: TeamCrestSnapshot | null, nextProgression: ProgressionSnapshot | null) => {
    if (!userId || !selectedGroupId) return;
    try {
      writeTeamIdentityCache(window.localStorage, userId, selectedGroupId, nextCrest, nextProgression);
    } catch {
      // Cache is derived and optional.
    }
  }, [selectedGroupId, userId]);

  const loadCrest = useCallback(async () => {
    if (!supabase || !selectedGroupId) return;
    const result = await supabase.rpc("get_pachanga_team_crest_snapshot_v1", { target_group_id: selectedGroupId });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    const canonical = normalizeTeamCrestSnapshot(result.data);
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
      setMessage(result.error.message);
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
        setMessage(result.error.message);
        return;
      }
      const groups = membershipsFromRows(result.data);
      setMemberships(groups);
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
      setCrest(cached?.crest ?? null);
      setProgression(cached?.progression ?? null);
      setMessage("");
    });
    queueMicrotask(() => void Promise.all([loadCrest(), loadProgression()]));
  }, [loadCrest, loadProgression, selectedGroupId, userId]);

  useEffect(() => {
    if (!crest) return;
    queueMicrotask(() => setDraftDesign(crest.canManage
      ? crest.draft?.design ?? crest.published?.design ?? crest.defaultDesign
      : crest.published?.design ?? crest.defaultDesign));
  }, [crest]);

  useEffect(() => {
    if (!supabase || !selectedGroupId || !userId) return;
    const client = supabase;
    const crestChannel = client
      .channel(`pachanga-crest-${selectedGroupId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_crest_state", filter: `group_id=eq.${selectedGroupId}` },
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

  function operationIdFor(fingerprint: string) {
    const existing = operationIds.current.get(fingerprint);
    if (existing) return existing;
    const created = crypto.randomUUID();
    operationIds.current.set(fingerprint, created);
    return created;
  }

  function acceptCrestCommit(value: unknown) {
    const canonical = normalizeTeamCrestSnapshot(value);
    if (!canonical || canonical.group.groupId !== selectedGroupId) return false;
    setCrest(canonical);
    persistCache(canonical, progression);
    return true;
  }

  async function saveDraft() {
    if (!supabase || !crest?.canManage || !draftDesign || busy) return;
    const fingerprint = `crest-save:${selectedGroupId}:${crest.crestRevision}:${JSON.stringify(draftDesign)}`;
    const operationId = operationIdFor(fingerprint);
    setBusy("save");
    setMessage("");
    const result = await supabase.rpc("save_pachanga_team_crest_draft_v1", {
      client_metadata: clientMetadata(),
      expected_revision: crest.crestRevision,
      operation_id: operationId,
      target_design: draftDesign,
      target_group_id: selectedGroupId,
    });
    setBusy("");
    if (result.error) {
      setMessage(result.error.message);
      if (result.error.code === "PT409") await loadCrest();
      return;
    }
    operationIds.current.delete(fingerprint);
    if (!acceptCrestCommit(result.data)) await loadCrest();
    setMessage("Borrador confirmado por el servidor.");
  }

  async function publishCrest() {
    if (!supabase || !crest?.canManage || !draftDesign || busy) return;
    const fingerprint = `crest-publish:${selectedGroupId}:${crest.crestRevision}:${crest.draft?.draftRevision ?? 0}`;
    const operationId = operationIdFor(fingerprint);
    setBusy("publish");
    setMessage("");
    const result = await supabase.rpc("publish_pachanga_team_crest_v1", {
      client_metadata: clientMetadata(),
      expected_revision: crest.crestRevision,
      operation_id: operationId,
      target_group_id: selectedGroupId,
    });
    setBusy("");
    if (result.error) {
      setMessage(result.error.message);
      if (result.error.code === "PT409") await loadCrest();
      return;
    }
    operationIds.current.delete(fingerprint);
    if (!acceptCrestCommit(result.data)) await loadCrest();
    setMessage("Escudo publicado para todo el equipo.");
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
      setMessage(result.error.message);
      if (result.error.code === "PT409") await loadProgression();
      return;
    }
    operationIds.current.delete(fingerprint);
    const opened = normalizePendingReward(result.data);
    if (opened) setOpenedReward(opened);
    await loadProgression();
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
    const nextIndex = rewardSequenceIndex + 1;
    if (nextIndex < rewardSequence.length) {
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

  const designIsSaved = Boolean(crest?.draft && draftDesign && JSON.stringify(crest.draft.design) === JSON.stringify(draftDesign));
  const activeTeamAchievements = progression?.teamAchievements.filter((item) => item.state === "active") ?? [];
  const activePersonalAchievements = progression?.personalAchievements.filter((item) => item.state === "active") ?? [];
  const personalAchievementCatalog = progression?.personalAchievementCatalog ?? [];
  const unlockedPersonalAchievements = personalAchievementCatalog.filter((item) => item.unlocked).length;
  const pendingRewards = progression?.rewards.filter((reward) => reward.status === "pending") ?? [];
  const openedRewards = progression?.rewards.filter((reward) => reward.status === "opened") ?? [];
  const rewardEconomy = progression?.rewardEconomy ?? null;
  const currentSequenceReward = rewardSequence[rewardSequenceIndex] ?? null;

  return (
    <main className={styles.page}>
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

      {!selectedGroupId ? <p className={styles.empty}>Necesitas pertenecer a un grupo para abrir su identidad.</p> : null}
      {crest && draftDesign ? (
        <>
          <section className={styles.crestBand}>
            <div className={styles.previewStage}>
              <CrestPreview catalog={crest.catalog} design={draftDesign} />
              <div>
                <span>{crest.published ? `Versión publicada ${crest.published.version}` : "Todavía sin publicar"}</span>
                <strong>{draftDesign.initials}</strong>
                <small>Revisión confirmada {crest.crestRevision}</small>
              </div>
            </div>

            {crest.canManage ? (
              <div className={styles.editor}>
                <div className={styles.initialsRow}>
                  <label>Iniciales<input maxLength={4} value={draftDesign.initials} onChange={(event) => setDraftDesign((current) => current ? { ...current, initials: event.target.value.toUpperCase().replace(/\s/g, "") } : current)} /></label>
                  <div className={styles.colorGroup}>
                    <span>Color principal</span>
                    <div>{crest.catalog.filter((item) => item.family === "color").map((item) => (
                      <button
                        aria-label={`Color principal ${item.name}`}
                        className={draftDesign.primaryColorKey === item.key ? styles.activeSwatch : ""}
                        key={`primary-${item.key}`}
                        style={{ background: typeof item.render.hex === "string" ? item.render.hex : "#fff" }}
                        type="button"
                        onClick={() => setDraftDesign((current) => current ? { ...current, primaryColorKey: item.key } : current)}
                      />
                    ))}</div>
                  </div>
                  <div className={styles.colorGroup}>
                    <span>Color secundario</span>
                    <div>{crest.catalog.filter((item) => item.family === "color").map((item) => (
                      <button
                        aria-label={`Color secundario ${item.name}`}
                        className={draftDesign.secondaryColorKey === item.key ? styles.activeSwatch : ""}
                        key={`secondary-${item.key}`}
                        style={{ background: typeof item.render.hex === "string" ? item.render.hex : "#fff" }}
                        type="button"
                        onClick={() => setDraftDesign((current) => current ? { ...current, secondaryColorKey: item.key } : current)}
                      />
                    ))}</div>
                  </div>
                </div>
                {(["shape", "pattern", "border", "symbol", "adornment", "palette", "effect"] as const).map((family) => (
                  <CatalogOptions
                    catalog={crest.catalog}
                    design={draftDesign}
                    family={family}
                    key={family}
                    onChange={(key) => setDraftDesign((current) => current ? {
                      ...current,
                      [family === "shape" ? "shapeKey"
                        : family === "pattern" ? "patternKey"
                          : family === "border" ? "borderKey"
                            : family === "symbol" ? "symbolKey"
                              : family === "adornment" ? "adornmentKey"
                                : family === "palette" ? "paletteKey" : "effectKey"]: key,
                    } : current)}
                  />
                ))}
                <div className={styles.editorActions}>
                  <button type="button" disabled={Boolean(busy)} onClick={() => void saveDraft()}>{busy === "save" ? "Guardando…" : "Guardar borrador"}</button>
                  <button className={styles.publishButton} type="button" disabled={Boolean(busy) || !designIsSaved} onClick={() => void publishCrest()}>{busy === "publish" ? "Publicando…" : "Publicar escudo"}</button>
                </div>
                {!designIsSaved ? <small className={styles.editorHint}>Guarda el borrador antes de publicar esta combinación.</small> : null}
              </div>
            ) : (
              <div className={styles.memberCrestCopy}>
                <strong>Escudo oficial</strong>
                <p>El historial y las piezas desbloqueadas pertenecen al equipo. Solo owner y admins pueden publicar cambios.</p>
              </div>
            )}
          </section>

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

          <section className={styles.progressBand}>
            <div>
              <header><span>Logros del equipo</span><strong>{activeTeamAchievements.length}</strong></header>
              <div className={styles.achievementGrid}>
                {activeTeamAchievements.map((achievement) => (
                  <article key={achievement.grantId}>
                    <span>{achievement.scope === "external" ? "Rivales" : "Pachangas"} · {achievement.rarity}</span>
                    <strong>{achievement.title}</strong>
                    <p>{achievement.description}</p>
                  </article>
                ))}
                {!activeTeamAchievements.length ? <p className={styles.empty}>Los logros aparecerán al finalizar partidos canónicos.</p> : null}
              </div>
            </div>
            <div>
              <header>
                <span>Mis logros</span>
                <strong>{personalAchievementCatalog.length
                  ? `${unlockedPersonalAchievements}/${personalAchievementCatalog.length}`
                  : activePersonalAchievements.length}</strong>
              </header>
              <div className={styles.achievementGrid}>
                {personalAchievementCatalog.length ? personalAchievementCatalog.map((achievement) => (
                  <article
                    className={achievement.unlocked ? styles.achievementUnlocked : styles.achievementLocked}
                    key={achievement.key}
                  >
                    <span>{achievement.scope === "external" ? "Rivales" : "Pachangas"} · {achievement.rarity}</span>
                    <strong>{achievement.title}</strong>
                    <p>{achievement.description}</p>
                    <div
                      aria-label={`Progreso ${achievement.currentValue} de ${achievement.threshold}`}
                      className={styles.achievementProgress}
                      role="progressbar"
                      aria-valuemax={achievement.threshold}
                      aria-valuemin={0}
                      aria-valuenow={Math.min(achievement.currentValue, achievement.threshold)}
                    >
                      <span style={{ width: `${achievement.progressPercent}%` }} />
                    </div>
                    <small className={styles.achievementStatus}>
                      {achievement.unlocked
                        ? achievement.repeatable
                          ? `${achievement.occurrenceCount} ${achievement.occurrenceCount === 1 ? "vez" : "veces"}`
                          : `Desbloqueado${achievement.awardedAt ? ` · ${new Date(achievement.awardedAt).toLocaleDateString("es-ES")}` : ""}`
                        : `${achievement.currentValue}/${achievement.threshold}`}
                    </small>
                  </article>
                )) : activePersonalAchievements.map((achievement) => (
                  <article className={styles.achievementUnlocked} key={achievement.grantId}>
                    <span>{achievement.scope === "external" ? "Rivales" : "Pachangas"} · {achievement.rarity}</span>
                    <strong>{achievement.title}</strong>
                    <p>{achievement.description}</p>
                  </article>
                ))}
                {!personalAchievementCatalog.length && !activePersonalAchievements.length
                  ? <p className={styles.empty}>Aún no hay insignias personales confirmadas.</p>
                  : null}
              </div>
              {activePersonalAchievements.length ? (
                <div className={styles.recognitionHistory}>
                  <strong>Historial personal</strong>
                  {activePersonalAchievements.slice(0, 8).map((achievement) => (
                    <span key={achievement.grantId}>
                      {achievement.title}
                      <small>{dateLabel(achievement.occurredAt)}</small>
                    </span>
                  ))}
                </div>
              ) : null}
            </div>
          </section>

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
                  <CrestPreview catalog={crest.catalog} compact design={version.design} />
                  <div><strong>Versión {version.version}</strong><small>{dateLabel(version.publishedAt)}</small></div>
                </article>
              ))}
              {!crest.history.length ? <p className={styles.empty}>La primera publicación quedará guardada aquí.</p> : null}
            </div>
          </section>
        </>
      ) : null}

      {message ? <p className={styles.message} aria-live="polite">{message}</p> : null}

      <RewardBoxDemo
        open={Boolean(currentSequenceReward)}
        onClose={closeRewardSequence}
        eyebrow={currentSequenceReward
          ? `Caja ${rewardSequenceIndex + 1} de ${rewardSequence.length} · ${currentSequenceReward.boxRarity}`
          : undefined}
        title={currentSequenceReward?.achievement.title}
        description={openedReward
          ? `Premio confirmado: ${rewardResultLabel(openedReward)}`
          : "El contenido permanece sellado hasta que abras esta caja."}
        actionDisabled={Boolean(busy)}
        actionLabel={openedReward
          ? rewardSequenceIndex + 1 < rewardSequence.length ? "Siguiente caja" : "Ver mis logros"
          : busy ? "Abriendo..." : "Abrir caja"}
        onAction={() => {
          if (!currentSequenceReward) return;
          if (openedReward) advanceRewardSequence();
          else void openReward(currentSequenceReward);
        }}
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
  );
}
