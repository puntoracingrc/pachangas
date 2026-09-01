"use client";

import Link from "next/link";
import Image from "next/image";
import { useCallback, useEffect, useMemo, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
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
  fetchedAt: string;
  profile: ProfileRow | null;
  teams: TeamSummary[];
};

const cacheVersion = "v3e";

function cacheKey(userId: string) {
  return `pachangas-profile-read-cache:${cacheVersion}:${userId}`;
}

function safeText(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function profileModalities(profile: ProfileRow | null) {
  const market = Array.isArray(profile?.market_modalities) ? profile.market_modalities.filter(Boolean) : [];
  if (market.length) return market;
  if (!profile?.assessment_summary || typeof profile.assessment_summary !== "object") return [];
  const initial = (profile.assessment_summary as { initial?: { modeShares?: Array<{ mode?: string; percentage?: number }> } }).initial;
  const modes = initial?.modeShares?.filter((mode) => Number(mode.percentage) > 0).map((mode) => mode.mode) ?? [];
  return modes.filter((mode): mode is string => Boolean(mode));
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
    return parsed && Array.isArray(parsed.teams) ? { ...parsed, profile: normalizeProfileRow(parsed.profile) } : null;
  } catch {
    return null;
  }
}

export function CanonicalPlayerProfile() {
  const [userId, setUserId] = useState("");
  const [snapshot, setSnapshot] = useState<ProfileSnapshot | null>(null);
  const [status, setStatus] = useState<"error" | "loading" | "offline" | "ready" | "signed-out">(() => supabase ? "loading" : "error");
  const [message, setMessage] = useState("");

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

    const [profileResult, membershipsResult] = await Promise.all([
      supabase
        .from("pachanga_player_profiles")
        .select("id,display_name,avatar,avatar_offset_x,avatar_offset_y,position,outfield_position,current_overall,current_facets,assessment_summary,market_enabled,market_zones,market_availability,market_modalities,profile_version,updated_at")
        .eq("user_id", targetUserId)
        .maybeSingle(),
      supabase
        .from("pachanga_group_members")
        .select("role,pachanga_groups(id,name,team_code)")
        .eq("user_id", targetUserId)
        .order("created_at", { ascending: true }),
    ]);

    if (profileResult.error || membershipsResult.error) {
      const cached = readCache(targetUserId);
      setSnapshot(cached);
      setStatus(cached ? "offline" : "error");
      setMessage(cached ? "No pudimos actualizar el perfil. Mostramos la última copia confirmada." : "No pudimos recuperar tu perfil. Vuelve a intentarlo.");
      return;
    }

    const teams = (membershipsResult.data ?? []).flatMap((membership) => {
      const raw = Array.isArray(membership.pachanga_groups) ? membership.pachanga_groups[0] : membership.pachanga_groups;
      if (!raw) return [];
      const role = membership.role === "owner" || membership.role === "admin" ? membership.role : "player";
      return [{ id: String(raw.id), name: safeText(raw.name, "Equipo"), role, teamCode: safeText(raw.team_code) } satisfies TeamSummary];
    });
    const next: ProfileSnapshot = { fetchedAt: new Date().toISOString(), profile: normalizeProfileRow(profileResult.data), teams };
    setSnapshot(next);
    setStatus("ready");
    setMessage("");
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
      .channel(`profile-v3e-${userId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "pachanga_player_profiles", filter: `user_id=eq.${userId}` }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "pachanga_group_members", filter: `user_id=eq.${userId}` }, reload)
      .subscribe((nextStatus) => { if (nextStatus === "SUBSCRIBED") reload(); });
    const reconnect = () => reload();
    window.addEventListener("online", reconnect);
    return () => {
      window.removeEventListener("online", reconnect);
      void client.removeChannel(channel);
    };
  }, [loadCanonical, userId]);

  const profile = snapshot?.profile ?? null;
  const team = snapshot?.teams[0] ?? null;
  const modalities = useMemo(() => profileModalities(profile), [profile]);
  const marketState = playerMarketPresentationState({ availability: profile?.market_availability, enabled: profile?.market_enabled, zones: profile?.market_zones });
  const facets = Object.entries(profile?.current_facets ?? {}).slice(0, 6).map(([key, value]) => ({ key, label: key.slice(0, 3).toUpperCase(), value: Math.round(Number(value) || 0) }));
  const editHref = team ? `/?mobile=perfil&edit=1&equipo=${encodeURIComponent(team.teamCode)}` : "/?social=profile";

  async function signOut() {
    await supabase?.auth.signOut();
    window.location.assign("/");
  }

  return (
    <OfficialProductShellV2
      account={{ avatarUrl: profile?.avatar ?? undefined, displayName: profile?.display_name, onSignOut: signOut, profileHref: "/perfil", teamHref: "/?mobile=equipo" }}
      active="perfil"
      context={{ detail: team ? `${team.name} · ${team.role}` : "Jugador sin equipo", eyebrow: "Identidad", id: team?.id ?? "profile", role: team?.role ?? "Jugador", status: status === "ready" ? "Confirmado" : status === "offline" ? "Copia local" : "Comprobando", title: profile?.display_name ?? "Mi perfil", type: team ? "team" : "profile" }}
      links={{ perfil: "/perfil" }}
      perspective={team?.role === "owner" ? "team-owner" : team?.role === "admin" ? "team-admin" : team ? "player" : "free-agent"}
    >
      <main className={styles.page} data-canonical-profile="v3e" data-profile-status={status}>
        {status === "loading" ? <section className={styles.state}><strong>Cargando tu perfil confirmado...</strong></section> : null}
        {status === "signed-out" ? <section className={styles.state}><span>Mi perfil</span><h1>Inicia sesión para ver tu identidad de jugador</h1><Link href="/">Volver a Inicio</Link></section> : null}
        {status === "error" && !snapshot ? <section className={styles.state}><span>Perfil no disponible</span><h1>No pudimos cargar tu ficha</h1><p>{message}</p><button type="button" onClick={() => userId && void loadCanonical(userId)}>Reintentar</button></section> : null}
        {snapshot || status === "offline" ? (
          <>
            <header className={styles.hero}>
              <div className={styles.avatar} style={{ position: "relative" }}>{profile?.avatar ? <Image alt={`Avatar de ${profile.display_name}`} fill sizes="92px" src={profile.avatar} unoptimized /> : <span aria-hidden="true">{(profile?.display_name ?? "J").slice(0, 1).toUpperCase()}</span>}</div>
              <div><span>Mi perfil</span><h1>{profile?.display_name ?? "Perfil deportivo pendiente"}</h1><p>{profile ? `${profile.position} · ${modalities.map(modalityLabel).join(" · ") || "Modalidad pendiente"}` : "Completa tu identidad cuando actives una ficha dentro de un equipo."}</p><small>{profile?.market_zones || "Zona general pendiente"}</small></div>
              <Link className={styles.primary} href={editHref}>Editar perfil</Link>
            </header>
            {message ? <p className={styles.notice} role="status">{message}</p> : null}
            <div className={styles.grid}>
              <section className={styles.summary}>
                <header><span>Identidad</span><h2>Resumen de perfil</h2></header>
                <dl>
                  <div><dt>Posición</dt><dd>{profile?.position ?? "Pendiente"}</dd></div>
                  <div><dt>Modalidad</dt><dd>{modalities.map(modalityLabel).join(", ") || "Pendiente"}</dd></div>
                  <div><dt>Disponibilidad</dt><dd>{profile?.market_availability || "No indicada"}</dd></div>
                  <div><dt>Equipo activo</dt><dd>{team?.name ?? "Sin equipo"}</dd></div>
                </dl>
              </section>
              <section className={styles.cardSection}>
                <header><span>Mi carta</span><h2>{profile?.current_overall ? "Identidad de juego" : "Tu carta aún no está creada"}</h2></header>
                {profile?.current_overall ? <PlayerCosmeticCard facets={facets} meta={team?.name ?? "Jugador sin equipo"} name={profile.display_name} photoAlt={`Foto de ${profile.display_name}`} photoSrc={profile.avatar ?? undefined} position={profile.position.slice(0, 3).toUpperCase()} score={Math.round(profile.current_overall)} /> : <p>La carta es opcional para entrar, buscar partidos o unirte a un equipo.</p>}
                <Link href="/personalizar-carta">{profile?.current_overall ? "Ver mi carta" : "Crear mi carta"}</Link>
              </section>
              <section className={styles.marketSection}>
                <header><span>Disponibilidad en Mercado</span><strong data-market-state={marketState}>{marketState}</strong></header>
                <p>{marketState === "PUBLICADO" ? "Otros equipos pueden encontrarte con la información deportiva permitida." : marketState === "PAUSADO" ? "Conservas tu configuración, pero ahora no apareces publicado." : "Tu perfil no se publica hasta que lo autorices expresamente."}</p>
                <Link href={editHref}>Configurar</Link>
              </section>
              <section className={styles.privacy}>
                <header><span>Privacidad</span><h2>Lo que no publicamos</h2></header>
                <p>Email, teléfono, fecha de nacimiento completa, coordenadas exactas, identidad Auth y notas privadas permanecen fuera de esta vista.</p>
              </section>
            </div>
          </>
        ) : null}
      </main>
    </OfficialProductShellV2>
  );
}
