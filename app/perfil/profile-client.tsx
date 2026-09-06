"use client";

import Link from "next/link";
import Image from "next/image";
import { useCallback, useEffect, useMemo, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import {
  modalityLabel as socialModalityLabel,
  normalizeCanonicalSocialProfile,
  normalizeSocialTeams,
  type CanonicalSocialProfile,
} from "../social-team-core-contract";
import { normalizePlayerCosmeticsSnapshot, type PlayerCosmeticsSnapshot } from "../player-cosmetics-contract";
import { CLIENT_VERSION } from "../client-version-contract";
import { currentClientDisplayMode, pwaBridgeSnapshot } from "../pwa-client-bridge";
import { playerMarketPresentationState } from "../social-onboarding-contract";
import { supabase } from "../supabaseClient";
import styles from "./profile.module.css";

type ProfileRow = {
  assessment_summary: unknown;
  avatar: string | null;
  avatar_offset_x: number | null;
  avatar_offset_y: number | null;
  current_facets: Record<string, number> | null;
  current_overall: number | null;
  display_name: string;
  id: string;
  market_availability: string | null;
  market_enabled: boolean;
  market_modalities: string[] | null;
  market_zones: string | null;
  outfield_position: string | null;
  position: string;
  profile_version: number;
  updated_at: string;
};

type TeamSummary = {
  id: string;
  name: string;
  role: "admin" | "owner" | "player";
  teamCode: string;
};

type ProfileSnapshot = {
  cosmetics: PlayerCosmeticsSnapshot | null;
  fetchedAt: string;
  profile: ProfileRow | null;
  socialProfile: CanonicalSocialProfile | null;
  teams: TeamSummary[];
};

const cacheVersion = "v3f";

function cacheKey(userId: string) {
  return `pachangas-profile-read-cache:${cacheVersion}:${userId}`;
}

function safeText(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function marketClientMetadata() {
  const bridge = pwaBridgeSnapshot();
  return {
    clientVersion: CLIENT_VERSION,
    displayMode: currentClientDisplayMode(),
    serviceWorkerVersion: bridge.serviceWorkerVersion,
    surface: "canonical-profile",
  };
}

function profileModalities(profile: ProfileRow | null) {
  const market = Array.isArray(profile?.market_modalities) ? profile.market_modalities.filter(Boolean) : [];
  if (market.length) return market;
  if (!profile?.assessment_summary || typeof profile.assessment_summary !== "object") return [];
  const initial = (profile.assessment_summary as { initial?: { modeShares?: Array<{ mode?: string; percentage?: number }> } }).initial;
  const modes = initial?.modeShares?.filter((mode) => Number(mode.percentage) > 0).map((mode) => mode.mode) ?? [];
  return modes.filter((mode): mode is string => Boolean(mode));
}

function assessmentCompleted(profile: ProfileRow | null, kind: "advanced" | "initial") {
  if (!profile?.assessment_summary || typeof profile.assessment_summary !== "object") return false;
  const entry = (profile.assessment_summary as Record<string, unknown>)[kind];
  return Boolean(entry && typeof entry === "object" && typeof (entry as { completedAt?: unknown }).completedAt === "string");
}

function modalityLabel(modality: string) {
  if (modality === "sala" || modality === "futsal_5") return "Fútbol sala";
  if (modality === "futbol11" || modality === "football_11") return "Fútbol 11";
  if (modality === "futbol7" || modality === "football_7") return "Fútbol 7";
  return modality;
}

function normalizeProfileRow(value: unknown): ProfileRow | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  if (!safeText(row.id) || !safeText(row.display_name)) return null;
  return {
    assessment_summary: row.assessment_summary,
    avatar: typeof row.avatar === "string" ? row.avatar : null,
    avatar_offset_x: Number.isFinite(Number(row.avatar_offset_x)) ? Number(row.avatar_offset_x) : null,
    avatar_offset_y: Number.isFinite(Number(row.avatar_offset_y)) ? Number(row.avatar_offset_y) : null,
    current_facets: row.current_facets && typeof row.current_facets === "object" ? row.current_facets as Record<string, number> : null,
    current_overall: Number.isFinite(Number(row.current_overall)) ? Number(row.current_overall) : null,
    display_name: safeText(row.display_name, "Jugador"),
    id: safeText(row.id),
    market_availability: typeof row.market_availability === "string" ? row.market_availability : null,
    market_enabled: row.market_enabled === true,
    market_modalities: Array.isArray(row.market_modalities) ? row.market_modalities.filter((item): item is string => typeof item === "string") : [],
    market_zones: typeof row.market_zones === "string" ? row.market_zones : null,
    outfield_position: typeof row.outfield_position === "string" ? row.outfield_position : null,
    position: safeText(row.position, "Posición pendiente"),
    profile_version: Math.max(0, Math.floor(Number(row.profile_version) || 0)),
    updated_at: safeText(row.updated_at),
  };
}

function readCache(userId: string): ProfileSnapshot | null {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(cacheKey(userId)) ?? "null") as ProfileSnapshot | null;
    return parsed && Array.isArray(parsed.teams) ? {
      ...parsed,
      cosmetics: normalizePlayerCosmeticsSnapshot(parsed.cosmetics),
      profile: normalizeProfileRow(parsed.profile),
      socialProfile: normalizeCanonicalSocialProfile(parsed.socialProfile),
    } : null;
  } catch {
    return null;
  }
}

export function CanonicalPlayerProfile() {
  const [userId, setUserId] = useState("");
  const [snapshot, setSnapshot] = useState<ProfileSnapshot | null>(null);
  const [status, setStatus] = useState<"error" | "loading" | "offline" | "ready" | "signed-out">(() => supabase ? "loading" : "error");
  const [message, setMessage] = useState("");
  const [marketBusy, setMarketBusy] = useState(false);

  const loadCanonical = useCallback(async (targetUserId: string) => {
    if (!supabase) {
      setStatus("error");
      setMessage("El perfil no está disponible ahora mismo.");
      return;
    }
    if (!navigator.onLine) {
      const cached = readCache(targetUserId);
      setSnapshot(cached);
      setStatus("offline");
      setMessage(cached ? "Mostrando la última copia confirmada." : "Sin conexión y sin una copia confirmada en este dispositivo.");
      return;
    }

    const [profileResult, socialProfileResult, membershipsResult, cosmeticsResult] = await Promise.all([
      supabase
        .from("pachanga_player_profiles")
        .select("id,display_name,avatar,avatar_offset_x,avatar_offset_y,position,outfield_position,current_overall,current_facets,assessment_summary,market_enabled,market_zones,market_availability,market_modalities,profile_version,updated_at")
        .eq("user_id", targetUserId)
        .maybeSingle(),
      supabase.rpc("get_my_pachanga_social_profile_v1"),
      supabase.rpc("get_my_pachanga_social_teams_v1"),
      supabase.rpc("get_pachanga_player_cosmetics_snapshot_v1"),
    ]);

    if (profileResult.error || membershipsResult.error) {
      const cached = readCache(targetUserId);
      setSnapshot(cached);
      setStatus(cached ? "offline" : "error");
      setMessage(cached ? "No pudimos actualizar el perfil. Mostramos la última copia confirmada." : "No pudimos recuperar tu perfil. Vuelve a intentarlo.");
      return;
    }

    const teams = normalizeSocialTeams(membershipsResult.data).map((team) => ({
      id: team.groupId,
      name: team.name,
      role: team.role,
      teamCode: team.teamCode,
    } satisfies TeamSummary));
    const cosmetics = cosmeticsResult.error
      ? readCache(targetUserId)?.cosmetics ?? null
      : normalizePlayerCosmeticsSnapshot(cosmeticsResult.data);
    const next: ProfileSnapshot = {
      cosmetics: cosmetics?.playerProfileId === profileResult.data?.id ? cosmetics : null,
      fetchedAt: new Date().toISOString(),
      profile: normalizeProfileRow(profileResult.data),
      socialProfile: socialProfileResult.error ? null : normalizeCanonicalSocialProfile(socialProfileResult.data),
      teams,
    };
    setSnapshot(next);
    setStatus("ready");
    setMessage(cosmeticsResult.error && profileResult.data ? "No pudimos actualizar el diseño de tu carta. Vuelve a intentarlo con conexión." : "");
    try {
      window.localStorage.setItem(cacheKey(targetUserId), JSON.stringify(next));
    } catch {
      // The canonical server snapshot remains available even if the read cache is full.
    }
  }, []);

  useEffect(() => {
    if (!supabase) return;
    let active = true;
    void supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      const id = data.session?.user?.id;
      if (!id) {
        setStatus("signed-out");
        return;
      }
      setUserId(id);
      const cached = readCache(id);
      if (cached) setSnapshot(cached);
      void loadCanonical(id);
    });
    return () => { active = false; };
  }, [loadCanonical]);

  useEffect(() => {
    if (!supabase || !userId) return;
    const client = supabase;
    const reload = () => void loadCanonical(userId);
    const channel = client
      .channel(`profile-v3f-${userId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "pachanga_player_profiles", filter: `user_id=eq.${userId}` }, reload)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_social_invalidations_v1" }, reload)
      .subscribe((nextStatus) => { if (nextStatus === "SUBSCRIBED") reload(); });
    const reconnect = () => reload();
    window.addEventListener("online", reconnect);
    window.addEventListener("focus", reconnect);
    window.addEventListener("pageshow", reconnect);
    return () => {
      window.removeEventListener("online", reconnect);
      window.removeEventListener("focus", reconnect);
      window.removeEventListener("pageshow", reconnect);
      void client.removeChannel(channel);
    };
  }, [loadCanonical, userId]);

  const profile = snapshot?.profile ?? null;
  const cosmetics = snapshot?.cosmetics?.enabled ? snapshot.cosmetics : null;
  const featuredAchievement = cosmetics?.featuredBadges.find((badge) => badge.grantId === cosmetics.loadout.featuredBadgeGrantId) ?? null;
  const socialProfile = snapshot?.socialProfile ?? null;
  const team = snapshot?.teams[0] ?? null;
  const modalities = useMemo(() => profileModalities(profile), [profile]);
  const freeAgentMarketReady = Boolean(
    socialProfile?.generalArea
      && socialProfile.usualDays.length
      && socialProfile.approximateTime,
  );
  const marketState = team
    ? playerMarketPresentationState({ availability: profile?.market_availability, enabled: profile?.market_enabled, zones: profile?.market_zones })
    : socialProfile?.marketPublished
      ? "PUBLICADO"
      : freeAgentMarketReady ? "PAUSADO" : "NO_CONFIGURADO";
  const facets = Object.entries(profile?.current_facets ?? {}).slice(0, 6).map(([key, value]) => ({ key, label: key.slice(0, 3).toUpperCase(), value: Math.round(Number(value) || 0) }));
  const editHref = "/?social=profile";
  const marketSettingsHref = team ? `/?grupo=${encodeURIComponent(team.id)}&mobile=perfil&market=1#market-profile` : editHref;
  const identityName = profile?.display_name ?? socialProfile?.displayName ?? "Mi perfil";
  const identityAvatar = profile?.avatar ?? socialProfile?.avatarRef ?? null;
  const identityPosition = profile?.position ?? socialProfile?.primaryPosition ?? "Pendiente";
  const identityModalities = modalities.length
    ? modalities.map(modalityLabel)
    : socialProfile ? [socialModalityLabel(socialProfile.preferredModality)] : [];
  const identityArea = profile?.market_zones || socialProfile?.generalArea || "Zona general pendiente";
  const initialAssessmentComplete = assessmentCompleted(profile, "initial");
  const advancedAssessmentComplete = assessmentCompleted(profile, "advanced");

  async function signOut() {
    await supabase?.auth.signOut();
    window.location.assign("/");
  }

  async function toggleFreeAgentMarket() {
    if (!supabase || !userId || !socialProfile || team || marketBusy) return;
    if (!navigator.onLine) {
      setMessage("Sin conexión: tu perfil no se ha publicado ni retirado.");
      return;
    }
    if (!socialProfile.marketPublished && !freeAgentMarketReady) {
      setMessage("Añade una zona, días y horario antes de publicar tu perfil.");
      return;
    }

    setMarketBusy(true);
    setMessage("");
    const nextPublished = !socialProfile.marketPublished;
    try {
      const result = await supabase.rpc("command_pachanga_free_agent_market_v1", {
        action: nextPublished ? "market.publish" : "market.unpublish",
        client_metadata: marketClientMetadata(),
        expected_revision: socialProfile.confirmedRevision,
        operation_id: crypto.randomUUID(),
        payload: {},
      });

      if (result.error) {
        setMessage(result.error.code === "PT409"
          ? "Tu perfil cambió en otro dispositivo. Hemos recuperado el estado confirmado."
          : "No pudimos cambiar tu publicación. No se ha confirmado ningún cambio.");
        if (result.error.code === "PT409") await loadCanonical(userId);
        return;
      }

      const confirmedProfile = normalizeCanonicalSocialProfile(result.data);
      if (!confirmedProfile) {
        setMessage("El servidor no devolvió un perfil válido. Hemos recuperado el estado confirmado.");
        await loadCanonical(userId);
        return;
      }
      const nextSnapshot: ProfileSnapshot = {
        cosmetics: snapshot?.cosmetics ?? null,
        fetchedAt: new Date().toISOString(),
        profile,
        socialProfile: confirmedProfile,
        teams: snapshot?.teams ?? [],
      };
      setSnapshot(nextSnapshot);
      try {
        window.localStorage.setItem(cacheKey(userId), JSON.stringify(nextSnapshot));
      } catch {
        // The response is already authoritative; this cache is optional.
      }
      setStatus("ready");
      setMessage(confirmedProfile.marketPublished
        ? "Tu perfil ya está publicado en Mercado."
        : "Tu perfil ya no aparece en Mercado.");
    } catch {
      setMessage("Se perdió la conexión antes de confirmar el cambio. Tu estado visible no se ha modificado.");
    } finally {
      setMarketBusy(false);
    }
  }

  return (
    <OfficialProductShellV2
      account={{ avatarUrl: identityAvatar ?? undefined, displayName: identityName, onSignOut: signOut, profileHref: "/perfil", teamHref: "/equipo" }}
      active="perfil"
      context={{ detail: team ? `${team.name} · ${team.role}` : "Jugador sin equipo", eyebrow: "Identidad", id: team?.id ?? "profile", role: team?.role ?? "Jugador", status: status === "ready" ? "Confirmado" : status === "offline" ? "Copia local" : "Comprobando", title: identityName, type: team ? "team" : "profile" }}
      links={{ perfil: "/perfil" }}
      perspective={team?.role === "owner" ? "team-owner" : team?.role === "admin" ? "team-admin" : team ? "player" : "free-agent"}
    >
      <main className={styles.page} data-canonical-profile="v3f" data-profile-status={status}>
        {status === "loading" ? <section className={styles.state}><strong>Cargando tu perfil confirmado...</strong></section> : null}
        {status === "signed-out" ? <section className={styles.state}><span>Mi perfil</span><h1>Inicia sesión para ver tu identidad de jugador</h1><Link href="/">Volver a Inicio</Link></section> : null}
        {status === "error" && !snapshot ? <section className={styles.state}><span>Perfil no disponible</span><h1>No pudimos cargar tu ficha</h1><p>{message}</p><button type="button" onClick={() => userId && void loadCanonical(userId)}>Reintentar</button></section> : null}
        {snapshot || status === "offline" ? (
          <>
            <header className={styles.hero}>
              <div className={styles.avatar} style={{ position: "relative" }}>{identityAvatar ? <Image alt={`Avatar de ${identityName}`} fill sizes="92px" src={identityAvatar} unoptimized /> : <span aria-hidden="true">{identityName.slice(0, 1).toUpperCase()}</span>}</div>
              <div><span>Mi perfil</span><h1>{identityName}</h1><p>{identityPosition} · {identityModalities.join(" · ") || "Modalidad pendiente"}</p><small>{identityArea}</small></div>
              <Link className={styles.primary} href={editHref}>Editar perfil</Link>
            </header>
            {message ? <p className={styles.notice} role="status">{message}</p> : null}
            <div className={styles.grid}>
              <section className={styles.summary}>
                <header><span>Identidad</span><h2>Resumen de perfil</h2></header>
                <dl>
                  <div><dt>Posición</dt><dd>{identityPosition}</dd></div>
                  <div><dt>Modalidad</dt><dd>{identityModalities.join(", ") || "Pendiente"}</dd></div>
                  <div><dt>Disponibilidad</dt><dd>{profile?.market_availability || socialProfile?.approximateTime || "No indicada"}</dd></div>
                  <div><dt>Equipo activo</dt><dd>{team?.name ?? "Sin equipo"}</dd></div>
                </dl>
              </section>
              <section className={styles.cardSection}>
                <header><span>Mi carta</span>{!initialAssessmentComplete ? <h2>Tu carta aún no está creada</h2> : null}</header>
                {initialAssessmentComplete && profile?.current_overall ? <PlayerCosmeticCard cosmetics={cosmetics?.owned} loadout={cosmetics?.loadout} featuredAchievement={featuredAchievement} facets={facets} meta={team?.name ?? "Jugador sin equipo"} name={profile.display_name} photoAlt={`Foto de ${profile.display_name}`} photoSrc={profile.avatar ?? undefined} position={profile.position.slice(0, 3).toUpperCase()} score={Math.round(profile.current_overall)} /> : <p>Responde unas preguntas sobre cómo juegas. Crearemos tu primera media y tus atributos. Después evolucionarán con partidos y valoraciones.</p>}
                <div className={styles.cardActions}>
                  <Link className={styles.primary} href={initialAssessmentComplete ? "/personalizar-carta" : "/perfil/test-inicial"}>
                    {initialAssessmentComplete ? "Editar carta" : "Hacer test inicial y crear mi carta"}
                  </Link>
                  {initialAssessmentComplete && !advancedAssessmentComplete ? <Link href="/perfil/test-inicial?tipo=avanzado">Mejorar precisión de mi carta</Link> : null}
                </div>
              </section>
              <section className={styles.marketSection}>
                <header><span>Mercado público</span><strong data-market-state={marketState}>{marketState === "PUBLICADO" ? "PUBLICADO" : "NO PUBLICADO"}</strong></header>
                <p>Activa el mercado público para que otros equipos te encuentren y te propongan jugar. También te permite encontrar equipos y buscar partidos a los que apuntarte.</p>
                {!team && !freeAgentMarketReady ? <p>Añade tu zona, días y horario. Después podrás pulsar «Publicarme» para activar tu publicación.</p> : null}
                <div className={styles.marketActions}>
                  {!team && socialProfile ? (
                    <button
                      data-free-agent-market-action={socialProfile.marketPublished ? "unpublish" : "publish"}
                      disabled={marketBusy || (!socialProfile.marketPublished && !freeAgentMarketReady)}
                      onClick={() => void toggleFreeAgentMarket()}
                      type="button"
                    >
                      {marketBusy ? "Confirmando..." : socialProfile.marketPublished ? "Pausar publicación" : "Publicarme"}
                    </button>
                  ) : null}
                  <Link href={marketSettingsHref}>{team ? "Configurar mercado público" : "Completar zona y disponibilidad"}</Link>
                </div>
              </section>
              <details className={styles.privacy}>
                <summary>Privacidad <span>Lo que no publicamos</span></summary>
                <p>Email, teléfono, fecha de nacimiento completa, coordenadas exactas, identidad Auth y notas privadas permanecen fuera de esta vista.</p>
              </details>
            </div>
          </>
        ) : null}
      </main>
    </OfficialProductShellV2>
  );
}
