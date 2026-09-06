"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { TeamShieldView } from "../_components/team-shield-view";
import {
  modalityLabel,
  normalizeCanonicalSocialProfile,
  normalizeSocialTeamFlags,
  normalizeSocialTeamHome,
  normalizeSocialTeamInvitations,
  normalizeSocialTeamMembershipRequests,
  normalizeSocialTeamRoster,
  normalizeSocialTeams,
  roleLabel,
  socialTeamCacheKey,
  socialTeamsCacheKey,
  type CanonicalSocialProfile,
  type SocialTeamCachedSnapshot,
  type SocialTeamFeatureFlags,
  type SocialTeamHome,
  type SocialTeamInvitation,
  type SocialTeamMembershipRequest,
  type SocialTeamRosterMember,
  type SocialTeamSummary,
} from "../social-team-core-contract";
import { supabase } from "../supabaseClient";
import styles from "./social-team.module.css";

type TeamSurface = "home" | "invitations" | "roster";
type TeamStatus = "disabled" | "error" | "loading" | "no-team" | "offline" | "ready" | "signed-out";

function readJson<T>(key: string): T | null {
  try {
    return JSON.parse(window.localStorage.getItem(key) ?? "null") as T | null;
  } catch {
    return null;
  }
}

function writeJson(key: string, value: unknown) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Local storage is an optional read cache, never the Team authority.
  }
}

function currentTeamRequest() {
  if (typeof window === "undefined") return "";
  return new URLSearchParams(window.location.search).get("team")?.trim() ?? "";
}

function commandMetadata() {
  if (typeof window === "undefined") return {};
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa" : "web",
  };
}

function dateLabel(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Fecha pendiente";
  return new Intl.DateTimeFormat("es-ES", {
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
  }).format(date);
}

function invitationStateLabel(state: SocialTeamInvitation["state"]) {
  if (state === "ACTIVE") return "Activa";
  if (state === "USED") return "Usada";
  if (state === "REVOKED") return "Revocada";
  if (state === "DECLINED") return "Rechazada";
  return "Caducada";
}

function safeCommandError(message: string, fallback: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes("stale") || normalized.includes("conflict")) return "El equipo cambió en otro dispositivo. Hemos recargado su versión oficial.";
  if (normalized.includes("team_admin_required")) return "Solo owner y admins pueden gestionar invitaciones.";
  if (normalized.includes("operationally_restricted") || normalized.includes("suspended") || normalized.includes("archived")) return "El estado operativo del equipo no permite esta acción.";
  if (normalized.includes("disabled")) return "Esta función todavía no está activa.";
  if (normalized.includes("client_update_required")) return "Actualiza Pachangas IQ para continuar.";
  return fallback;
}

function cachedTeamSnapshot(userId: string, groupId: string) {
  const cached = readJson<SocialTeamCachedSnapshot>(socialTeamCacheKey(userId, groupId));
  const home = normalizeSocialTeamHome(cached?.home);
  if (!cached || !home) return null;
  return {
    fetchedAt: cached.fetchedAt,
    home,
    invitations: normalizeSocialTeamInvitations(cached.invitations),
    roster: normalizeSocialTeamRoster(cached.roster),
  } satisfies SocialTeamCachedSnapshot;
}

export function SocialTeamProduct({ surface = "home" }: { surface?: TeamSurface }) {
  const [userId, setUserId] = useState("");
  const [flags, setFlags] = useState<SocialTeamFeatureFlags | null>(null);
  const [profile, setProfile] = useState<CanonicalSocialProfile | null>(null);
  const [teams, setTeams] = useState<SocialTeamSummary[]>([]);
  const [selectedTeamId, setSelectedTeamId] = useState("");
  const [home, setHome] = useState<SocialTeamHome | null>(null);
  const [roster, setRoster] = useState<SocialTeamRosterMember[]>([]);
  const [invitations, setInvitations] = useState<SocialTeamInvitation[]>([]);
  const [membershipRequests, setMembershipRequests] = useState<SocialTeamMembershipRequest[]>([]);
  const [status, setStatus] = useState<TeamStatus>(() => supabase ? "loading" : "error");
  const [message, setMessage] = useState("");
  const [busyInvitationId, setBusyInvitationId] = useState("");
  const [busyRequestId, setBusyRequestId] = useState("");
  const [creatingInvite, setCreatingInvite] = useState(false);
  const [expiryHours, setExpiryHours] = useState(168);
  const [freshShareUrl, setFreshShareUrl] = useState("");
  const [freshInviteMode, setFreshInviteMode] = useState<SocialTeamInvitation["inviteMode"]>("TEAM_LINK");
  const [copyConfirmed, setCopyConfirmed] = useState(false);

  const applyCached = useCallback((targetUserId: string, targetGroupId: string) => {
    const cachedTeams = normalizeSocialTeams(readJson<unknown>(socialTeamsCacheKey(targetUserId)));
    const cached = cachedTeamSnapshot(targetUserId, targetGroupId || cachedTeams[0]?.groupId || "");
    if (cachedTeams.length) setTeams(cachedTeams);
    if (cached) {
      setSelectedTeamId(cached.home.groupId);
      setHome(cached.home);
      setRoster(cached.roster);
      setInvitations(cached.invitations);
      setMembershipRequests([]);
      return true;
    }
    return false;
  }, []);

  const loadCanonical = useCallback(async (preferredTeam = "") => {
    if (!supabase) {
      setStatus("error");
      setMessage("No se puede conectar con Pachangas IQ.");
      return;
    }
    const session = await supabase.auth.getSession();
    const actorId = session.data.session?.user?.id ?? "";
    if (!actorId) {
      setStatus("signed-out");
      setMessage("");
      return;
    }
    setUserId(actorId);
    const requested = preferredTeam || currentTeamRequest() || window.localStorage.getItem("pachangas-social-team-selected-v1") || "";
    if (!navigator.onLine) {
      const restored = applyCached(actorId, requested);
      setStatus(restored ? "offline" : "error");
      setMessage(restored ? "Mostrando la última copia confirmada. Las acciones están bloqueadas sin conexión." : "Necesitas conexión para cargar tu equipo por primera vez.");
      return;
    }

    const [flagsResult, teamsResult, profileResult] = await Promise.all([
      supabase.rpc("get_pachanga_social_team_feature_flags_v1"),
      supabase.rpc("get_my_pachanga_social_teams_v1"),
      supabase.rpc("get_my_pachanga_social_profile_v1"),
    ]);
    if (flagsResult.error || teamsResult.error) {
      const restored = applyCached(actorId, requested);
      setStatus(restored ? "offline" : "error");
      setMessage(restored ? "No pudimos revalidar el equipo. Mostramos la última copia confirmada." : "No pudimos recuperar tus equipos.");
      return;
    }
    const nextFlags = normalizeSocialTeamFlags(flagsResult.data);
    const nextTeams = normalizeSocialTeams(teamsResult.data);
    const nextProfile = !profileResult.error ? normalizeCanonicalSocialProfile(profileResult.data) : null;
    setFlags(nextFlags);
    setProfile(nextProfile);
    setTeams(nextTeams);
    writeJson(socialTeamsCacheKey(actorId), nextTeams);
    if (!nextFlags?.socialTeamHomeV3fEnabled) {
      setStatus("disabled");
      setMessage("La portada social de equipo todavía no está activa.");
      return;
    }
    if (!nextTeams.length) {
      setSelectedTeamId("");
      setHome(null);
      setRoster([]);
      setInvitations([]);
      setMembershipRequests([]);
      setStatus("no-team");
      setMessage("");
      return;
    }
    const selected = nextTeams.find((team) => team.groupId === requested || team.teamCode === requested.toUpperCase()) ?? nextTeams[0];
    setSelectedTeamId(selected.groupId);
    window.localStorage.setItem("pachangas-social-team-selected-v1", selected.groupId);
    const isAdmin = selected.role === "owner" || selected.role === "admin";
    const [homeResult, rosterResult, invitationResult, membershipRequestResult] = await Promise.all([
      supabase.rpc("get_pachanga_social_team_home_v1", { target_group_id: selected.groupId }),
      supabase.rpc("get_pachanga_team_players_v1", { target_group_id: selected.groupId }),
      isAdmin ? supabase.rpc("get_pachanga_social_team_invitations_v2", { target_group_id: selected.groupId }) : Promise.resolve({ data: [], error: null }),
      isAdmin ? supabase.rpc("get_pachanga_team_membership_requests_v1", { target_group_id: selected.groupId }) : Promise.resolve({ data: [], error: null }),
    ]);
    if (homeResult.error || rosterResult.error || invitationResult.error || membershipRequestResult.error) {
      const restored = applyCached(actorId, selected.groupId);
      setStatus(restored ? "offline" : "error");
      setMessage(restored ? "No pudimos revalidar el equipo. Mostramos la última copia confirmada." : "No pudimos recuperar la portada del equipo.");
      return;
    }
    const nextHome = normalizeSocialTeamHome(homeResult.data);
    if (!nextHome) {
      setStatus("error");
      setMessage("El servidor respondió sin una portada canónica válida.");
      return;
    }
    const nextRoster = normalizeSocialTeamRoster(rosterResult.data);
    const nextInvitations = normalizeSocialTeamInvitations(invitationResult.data);
    const nextMembershipRequests = normalizeSocialTeamMembershipRequests(membershipRequestResult.data);
    setHome(nextHome);
    setRoster(nextRoster);
    setInvitations(nextInvitations);
    setMembershipRequests(nextMembershipRequests);
    setStatus("ready");
    setMessage(new URLSearchParams(window.location.search).get("created") === "1" ? "Equipo creado y confirmado por el servidor." : "");
    writeJson(socialTeamCacheKey(actorId, selected.groupId), {
      fetchedAt: new Date().toISOString(),
      home: nextHome,
      invitations: nextInvitations,
      roster: nextRoster,
    } satisfies SocialTeamCachedSnapshot);
  }, [applyCached]);

  useEffect(() => {
    queueMicrotask(() => void loadCanonical());
  }, [loadCanonical]);

  useEffect(() => {
    if (!supabase || !userId) return;
    const client = supabase;
    const reload = () => void loadCanonical(selectedTeamId);
    const channel = client
      .channel(`social-team-v3f-${userId}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_social_invalidations_v1" }, reload)
      .subscribe((nextStatus) => { if (nextStatus === "SUBSCRIBED") reload(); });
    const online = () => reload();
    const offline = () => {
      const restored = applyCached(userId, selectedTeamId);
      setStatus(restored ? "offline" : "error");
      setMessage("Sin conexión: puedes consultar la copia confirmada, pero no modificarla.");
    };
    window.addEventListener("online", online);
    window.addEventListener("offline", offline);
    return () => {
      window.removeEventListener("online", online);
      window.removeEventListener("offline", offline);
      void client.removeChannel(channel);
    };
  }, [applyCached, loadCanonical, selectedTeamId, userId]);

  const groupedRoster = useMemo(() => ({
    admins: roster.filter((member) => member.role === "owner" || member.role === "admin"),
    players: roster.filter((member) => member.role === "player"),
  }), [roster]);
  const contextOptions = teams.map((team) => ({
    detail: `${modalityLabel(team.modality)} · ${team.generalArea}`,
    id: team.groupId,
    nextAction: "Ver equipo",
    role: roleLabel(team.role),
    status: team.operationalStatus,
    title: team.name,
    type: "team" as const,
  }));
  const perspective = home?.role === "owner" ? "team-owner" : home?.role === "admin" ? "team-admin" : home ? "player" : "free-agent";

  function selectTeam(groupId: string) {
    setFreshShareUrl("");
    setCopyConfirmed(false);
    setStatus("loading");
    const params = new URLSearchParams(window.location.search);
    params.set("team", groupId);
    params.delete("created");
    window.history.replaceState(null, "", `${window.location.pathname}?${params.toString()}`);
    void loadCanonical(groupId);
  }

  async function createInvitation(inviteMode: SocialTeamInvitation["inviteMode"]) {
    if (!navigator.onLine) {
      setMessage("Necesitas conexión para confirmar esta acción.");
      return;
    }
    if (!supabase || !home || creatingInvite || !home.actions.canInvitePlayers) return;
    setCreatingInvite(true);
    setFreshShareUrl("");
    setCopyConfirmed(false);
    setMessage(inviteMode === "TEAM_LINK" ? "Creando el enlace del equipo..." : "Creando una invitación individual...");
    const result = await supabase.rpc("command_pachanga_team_player_invitation_v2", {
      action: "team.invitation.create",
      client_metadata: commandMetadata(),
      expected_revision: home.revision,
      invitation_token: null,
      operation_id: crypto.randomUUID(),
      payload: { expiresInHours: expiryHours, inviteMode, maxUses: inviteMode === "TEAM_LINK" ? 100 : 1 },
      target_group_id: home.groupId,
      target_invitation_id: null,
    });
    setCreatingInvite(false);
    if (result.error) {
      setMessage(safeCommandError(result.error.message, "No se pudo crear la invitación."));
      await loadCanonical(home.groupId);
      return;
    }
    const token = result.data && typeof result.data === "object" && "shareToken" in result.data ? String(result.data.shareToken ?? "") : "";
    if (!/^piq_[0-9a-f]{64}$/.test(token)) {
      setMessage(inviteMode === "TEAM_LINK"
        ? "El enlace del equipo se confirmó, pero su token ya no puede volver a mostrarse."
        : "La invitación se confirmó, pero su enlace de un solo uso ya no puede volver a mostrarse.");
      await loadCanonical(home.groupId);
      return;
    }
    setFreshShareUrl(`${window.location.origin}/invitacion/grupo/${encodeURIComponent(token)}`);
    setFreshInviteMode(inviteMode);
    setMessage(inviteMode === "TEAM_LINK"
      ? "Enlace del equipo confirmado. Cópialo ahora: el token no se volverá a mostrar."
      : "Invitación individual confirmada. Cópiala ahora: el token no se volverá a mostrar.");
    await loadCanonical(home.groupId);
  }

  async function revokeInvitation(invitation: SocialTeamInvitation) {
    if (!navigator.onLine) {
      setMessage("Necesitas conexión para confirmar esta acción.");
      return;
    }
    if (!supabase || !home || busyInvitationId) return;
    setBusyInvitationId(invitation.invitationId);
    setMessage("Revocando invitación...");
    const result = await supabase.rpc("command_pachanga_team_player_invitation_v2", {
      action: "team.invitation.revoke",
      client_metadata: commandMetadata(),
      expected_revision: invitation.revision,
      invitation_token: null,
      operation_id: crypto.randomUUID(),
      payload: {},
      target_group_id: home.groupId,
      target_invitation_id: invitation.invitationId,
    });
    setBusyInvitationId("");
    if (result.error) setMessage(safeCommandError(result.error.message, "No se pudo revocar la invitación."));
    else setMessage("Invitación revocada por el servidor.");
    await loadCanonical(home.groupId);
  }

  async function respondMembershipRequest(request: SocialTeamMembershipRequest, response: "accept" | "reject") {
    if (!navigator.onLine) {
      setMessage("Necesitas conexión para confirmar esta acción.");
      return;
    }
    if (!supabase || !home || busyRequestId || request.state !== "PENDING") return;
    setBusyRequestId(request.requestId);
    setMessage(response === "accept" ? "Aceptando al jugador..." : "Rechazando la solicitud...");
    const result = await supabase.rpc("command_pachanga_team_membership_request_v1", {
      action: `team.membership.request.${response}`,
      client_metadata: commandMetadata(),
      expected_revision: request.revision,
      operation_id: crypto.randomUUID(),
      payload: {},
      target_group_id: home.groupId,
      target_request_id: request.requestId,
    });
    setBusyRequestId("");
    if (result.error) setMessage(safeCommandError(result.error.message, "No se pudo responder la solicitud."));
    else setMessage(response === "accept" ? "Jugador añadido al equipo." : "Solicitud rechazada.");
    await loadCanonical(home.groupId);
  }

  async function copyShareUrl() {
    if (!freshShareUrl) return;
    try {
      await navigator.clipboard.writeText(freshShareUrl);
      setCopyConfirmed(true);
      setMessage(freshInviteMode === "TEAM_LINK" ? "Enlace del equipo copiado." : "Invitación individual copiada.");
      window.setTimeout(() => setCopyConfirmed(false), 2400);
    } catch {
      setCopyConfirmed(false);
      setMessage("No pudimos copiarlo automáticamente. Mantén pulsado el enlace para copiarlo.");
    }
  }

  async function shareInvitation() {
    if (!freshShareUrl) return;
    if (navigator.share) {
      try {
        await navigator.share({ text: `Invitación para ${home?.name ?? "mi equipo"}`, title: "Pachangas IQ", url: freshShareUrl });
        return;
      } catch {
        // A cancelled native share does not change the invitation.
      }
    }
    await copyShareUrl();
  }

  async function signOut() {
    await supabase?.auth.signOut();
    window.location.assign("/");
  }

  const shell = (content: React.ReactNode) => (
    <OfficialProductShellV2
      account={{ avatarUrl: profile?.avatarRef ?? undefined, displayName: profile?.displayName, onSignOut: signOut, profileHref: "/perfil", teamHref: "/equipo" }}
      active="equipo"
      context={{
        detail: home ? `${modalityLabel(home.modality)} · ${home.generalArea}` : "Tu espacio social",
        eyebrow: "Equipo",
        id: home?.groupId ?? "profile",
        role: home ? roleLabel(home.role) : "Jugador",
        status: status === "ready" ? "En directo" : status === "offline" ? "Copia local" : "Servidor",
        title: home?.name ?? profile?.displayName ?? "Mi equipo",
        type: home ? "team" : "profile",
      }}
      contextOptions={contextOptions.length ? contextOptions : undefined}
      contextVisual={home ? <TeamShieldView config={home.shield} label={`Escudo de ${home.name}`} size={32} /> : undefined}
      links={{ equipo: "/equipo" }}
      onContextChange={selectTeam}
      perspective={perspective}
    >
      {content}
    </OfficialProductShellV2>
  );

  if (status === "loading") return shell(<main className={styles.page}><section className={styles.state}><span>Equipo</span><h1>Cargando tu estado confirmado...</h1></section></main>);
  if (status === "signed-out") return shell(<main className={styles.page}><section className={styles.state}><span>Mi equipo</span><h1>Inicia sesión para abrir tu equipo</h1><Link className={styles.primary} href="/">Volver a Inicio</Link></section></main>);
  if (status === "disabled") return shell(<main className={styles.page}><section className={styles.state}><span>Equipo</span><h1>La portada social se está preparando</h1><p>{message}</p><Link href="/?mobile=inicio">Volver a Inicio</Link></section></main>);
  if (status === "no-team") return shell(<main className={styles.page}><section className={styles.state}><span>Tu espacio de jugador</span><h1>Aún no perteneces a un equipo</h1><p>Tu perfil sigue disponible. Puedes entrar mediante una invitación, crear tu equipo o buscar una pachanga.</p><div className={styles.stateActions}><Link className={styles.primary} href="/?social=create">Crear mi equipo</Link><Link href="/?social=join">Unirme a un equipo</Link><Link href="/mercado?tab=partidos">Buscar partido</Link></div></section></main>);
  if (!home) return shell(<main className={styles.page}><section className={styles.state}><span>Equipo no disponible</span><h1>No pudimos abrir una copia válida</h1><p>{message}</p><button type="button" onClick={() => void loadCanonical(selectedTeamId)}>Reintentar</button></section></main>);

  return shell(
    <main className={styles.page} data-social-team-status={status} data-social-team-surface={surface}>
      <header className={styles.hero}>
        <TeamShieldView className={styles.heroShield} config={home.shield} label={`Escudo de ${home.name}`} size={210} />
        <div className={styles.heroCopy}>
          <span>Equipo activo</span>
          <h1>{home.name}</h1>
          <p>{modalityLabel(home.modality)} · {home.generalArea || "Zona pendiente"}</p>
          <small>{roster.length} jugadores</small>
        </div>
        {surface === "home" ? <PrimaryTeamAction home={home} /> : <Link className={styles.primary} href={`/equipo?team=${encodeURIComponent(home.groupId)}`}>Volver al equipo</Link>}
      </header>

      {message ? <p className={styles.notice} role="status">{message}</p> : null}

      <nav className={styles.subnav} aria-label="Secciones del equipo">
        <Link aria-current={surface === "home" ? "page" : undefined} href={`/equipo?team=${encodeURIComponent(home.groupId)}`}>Portada</Link>
        <Link aria-current={surface === "roster" ? "page" : undefined} href={`/equipo/plantilla?team=${encodeURIComponent(home.groupId)}`}>Plantilla</Link>
        {home.actions.canInvitePlayers ? <Link aria-current={surface === "invitations" ? "page" : undefined} href={`/equipo/invitaciones?team=${encodeURIComponent(home.groupId)}`}>Invitaciones</Link> : null}
      </nav>

      {surface === "home" ? <TeamHome home={home} roster={roster} /> : null}
      {surface === "roster" ? <RosterView admins={groupedRoster.admins} invitationCount={home.activeInvitationCount} players={groupedRoster.players} canInvite={home.actions.canInvitePlayers} teamId={home.groupId} /> : null}
      {surface === "invitations" ? <InvitationView
        busyInvitationId={busyInvitationId}
        busyRequestId={busyRequestId}
        canInvite={home.actions.canInvitePlayers && flags?.socialTeamInvitationV2Enabled === true}
        copyConfirmed={copyConfirmed}
        creating={creatingInvite}
        expiryHours={expiryHours}
        freshShareUrl={freshShareUrl}
        freshInviteMode={freshInviteMode}
        invitations={invitations}
        membershipRequests={membershipRequests}
        onCopy={() => void copyShareUrl()}
        onCreate={(inviteMode) => void createInvitation(inviteMode)}
        onExpiryChange={setExpiryHours}
        onRevoke={(invitation) => void revokeInvitation(invitation)}
        onRespondRequest={(request, response) => void respondMembershipRequest(request, response)}
        onShare={() => void shareInvitation()}
        teamCode={home.teamCode}
        writeEnabled={status === "ready"}
      /> : null}
    </main>,
  );
}

function PrimaryTeamAction({ home }: { home: SocialTeamHome }) {
  if (home.nextMatch) {
    return <Link className={styles.primary} href={`/?mobile=partido&equipo=${encodeURIComponent(home.teamCode)}&p=${encodeURIComponent(home.nextMatch.matchId)}`}>Ver partido</Link>;
  }
  if (home.actions.canCreateMatch) {
    return <Link className={styles.primary} href={`/?mobile=partido&equipo=${encodeURIComponent(home.teamCode)}&create=match`}>Crear primer partido</Link>;
  }
  return <Link className={styles.primary} href={`/equipo/plantilla?team=${encodeURIComponent(home.groupId)}`}>Ver plantilla</Link>;
}

function TeamHome({ home, roster }: { home: SocialTeamHome; roster: SocialTeamRosterMember[] }) {
  return (
    <div className={styles.homeGrid}>
      <section className={styles.nextMatch}>
        <header><span>Próximo partido</span><h2>{home.nextMatch?.title ?? "Aún no hay partido"}</h2></header>
        {home.nextMatch ? <><p>{dateLabel(home.nextMatch.date)} · {home.nextMatch.place || "Campo por confirmar"}</p><small>{modalityLabel(home.nextMatch.modality)} · objetivo {home.nextMatch.targetPlayers} jugadores</small></> : <p>Crea el primer partido cuando la plantilla esté preparada.</p>}
      </section>
      <section className={styles.rosterPreview}>
        <header><span>Plantilla</span><h2>{roster.length} jugadores</h2></header>
        <div>{roster.slice(0, 6).map((member) => <MemberAvatar key={member.memberKey} member={member} />)}</div>
        <Link href={`/equipo/plantilla?team=${encodeURIComponent(home.groupId)}`}>Ver plantilla</Link>
      </section>
      <section className={styles.activity}>
        <header><span>Equipo</span><h2>Ahora mismo</h2></header>
        <ul><li><b>{roster.length}</b><span>jugadores</span></li><li><b>{home.activeInvitationCount}</b><span>invitaciones pendientes</span></li>{home.operationalStatus !== "ACTIVE" ? <li><b>{home.operationalStatus}</b><span>acción limitada</span></li> : null}</ul>
      </section>
      <section className={styles.destinations}>
        <header><span>Jugar</span><h2>Siguientes pasos</h2></header>
        <div><Link href="/retos">Retar equipo</Link><Link href="/mercado">Abrir Mercado</Link></div>
      </section>
    </div>
  );
}

function MemberAvatar({ member }: { member: SocialTeamRosterMember }) {
  return <span className={styles.memberAvatar} title={member.displayName}>{member.avatarRef ? <Image alt="" fill sizes="44px" src={member.avatarRef} unoptimized /> : member.displayName.slice(0, 1).toUpperCase()}</span>;
}

function RosterView({ admins, canInvite, invitationCount, players, teamId }: { admins: SocialTeamRosterMember[]; canInvite: boolean; invitationCount: number; players: SocialTeamRosterMember[]; teamId: string }) {
  return (
    <div className={styles.rosterSections}>
      {admins.length ? <RosterGroup members={admins} title="Jugadores administradores" /> : null}
      {players.length ? <RosterGroup members={players} title="Jugadores" /> : null}
      {!admins.length && !players.length ? <p>Aún no hay jugadores en la plantilla.</p> : null}
      {canInvite ? <section className={styles.invitationSummary}><div><span>Invitaciones pendientes</span><strong>{invitationCount}</strong></div><Link href={`/equipo/invitaciones?team=${encodeURIComponent(teamId)}`}>Gestionar</Link></section> : null}
    </div>
  );
}

function RosterGroup({ members, title }: { members: SocialTeamRosterMember[]; title: string }) {
  return <section className={styles.rosterGroup}><header><span>{title}</span><strong>{members.length}</strong></header><div className={styles.rosterList}>{members.map((member) => <details key={member.memberKey}><summary><MemberAvatar member={member} /><span><strong>{member.displayName}{member.isCurrentUser ? " · Tú" : ""}</strong><small>{member.primaryPosition}</small></span><b>{roleLabel(member.role)}</b></summary><div><span>{modalityLabel(member.preferredModality)}</span>{member.joinedAt ? <small>Miembro desde {dateLabel(member.joinedAt)}</small> : null}{member.isCurrentUser ? <Link href="/perfil">Abrir mi perfil</Link> : null}</div></details>)}</div></section>;
}

function InvitationView({ busyInvitationId, busyRequestId, canInvite, copyConfirmed, creating, expiryHours, freshInviteMode, freshShareUrl, invitations, membershipRequests, onCopy, onCreate, onExpiryChange, onRespondRequest, onRevoke, onShare, teamCode, writeEnabled }: {
  busyInvitationId: string;
  busyRequestId: string;
  canInvite: boolean;
  copyConfirmed: boolean;
  creating: boolean;
  expiryHours: number;
  freshInviteMode: SocialTeamInvitation["inviteMode"];
  freshShareUrl: string;
  invitations: SocialTeamInvitation[];
  membershipRequests: SocialTeamMembershipRequest[];
  onCopy: () => void;
  onCreate: (inviteMode: SocialTeamInvitation["inviteMode"]) => void;
  onExpiryChange: (hours: number) => void;
  onRespondRequest: (request: SocialTeamMembershipRequest, response: "accept" | "reject") => void;
  onRevoke: (invitation: SocialTeamInvitation) => void;
  onShare: () => void;
  teamCode: string;
  writeEnabled: boolean;
}) {
  if (!canInvite) return <section className={styles.state}><span>Invitaciones</span><h1>Solo owner y admins pueden crear enlaces</h1><p>Los jugadores pueden consultar la plantilla, pero no conceder membresías.</p></section>;
  return (
    <div className={styles.invitationLayout}>
      <section className={styles.inviteComposer}>
        <header><span>Enlace del equipo</span><h2>Invita a tus amigos</h2></header>
        <p>Comparte el mismo enlace con tu grupo. Podrá usarse hasta que caduque o lo revoques y cada persona entrará únicamente como jugador.</p>
        <label>Caducidad<select value={expiryHours} onChange={(event) => onExpiryChange(Number(event.target.value))}><option value={24}>24 horas</option><option value={72}>3 días</option><option value={168}>7 días</option><option value={336}>14 días</option></select></label>
        {!writeEnabled ? <p className={styles.notice}>Necesitas conexión para confirmar esta acción.</p> : null}
        <button className={styles.primary} type="button" disabled={creating || !writeEnabled} onClick={() => onCreate("TEAM_LINK")}>{creating ? "Creando..." : "Crear enlace para compartir"}</button>
        {freshShareUrl ? <div className={styles.freshInvite} role="status"><span>{freshInviteMode === "TEAM_LINK" ? "Enlace reutilizable" : "Invitación de un solo uso"}</span><a href={freshShareUrl}>{freshShareUrl}</a><div><button type="button" onClick={onCopy}>{copyConfirmed ? "Copiado" : "Copiar"}</button><button type="button" onClick={onShare}>Compartir</button></div>{copyConfirmed ? <small>Enlace copiado al portapapeles.</small> : null}</div> : null}
        <div className={styles.individualInvite}><div><strong>Invitación individual</strong><small>Genera un enlace distinto que solo podrá aceptar una persona.</small></div><button type="button" disabled={creating || !writeEnabled} onClick={() => onCreate("INDIVIDUAL")}>Crear enlace de un solo uso</button></div>
        <div className={styles.teamCode}><span>Código del equipo</span><strong>{teamCode}</strong><small>Identifica al equipo, pero no permite unirse.</small></div>
      </section>
      <section className={styles.invitationHistory}>
        <header><span>Historial</span><h2>Invitaciones</h2></header>
        {invitations.length ? <div>{invitations.map((invitation) => <article key={invitation.invitationId} data-invitation-state={invitation.state}><div><strong>{invitation.inviteMode === "TEAM_LINK" ? "Enlace del equipo" : invitationStateLabel(invitation.state)}</strong><small>{invitation.inviteMode === "TEAM_LINK" ? `${invitation.useCount} accesos · ${invitationStateLabel(invitation.state)}` : `Creada por ${invitation.createdByName}`}</small></div><p>{dateLabel(invitation.createdAt)} · caduca {dateLabel(invitation.expiresAt)}</p>{invitation.state === "ACTIVE" ? <button type="button" disabled={!writeEnabled || busyInvitationId === invitation.invitationId} onClick={() => onRevoke(invitation)}>{busyInvitationId === invitation.invitationId ? "Revocando..." : "Revocar"}</button> : null}</article>)}</div> : <p>No hay invitaciones creadas.</p>}
      </section>
      <section className={styles.membershipRequests}>
        <header><span>Solicitudes por código</span><h2>Pendientes de aprobación</h2></header>
        {membershipRequests.filter((request) => request.state === "PENDING").length ? (
          <div>{membershipRequests.filter((request) => request.state === "PENDING").map((request) => (
            <article key={request.requestId}>
              <div><strong>{request.requesterName}</strong><small>{request.requesterPrimaryPosition}</small></div>
              <div className={styles.requestActions}>
                <button type="button" disabled={!writeEnabled || busyRequestId === request.requestId} onClick={() => onRespondRequest(request, "reject")}>Rechazar</button>
                <button className={styles.primary} type="button" disabled={!writeEnabled || busyRequestId === request.requestId} onClick={() => onRespondRequest(request, "accept")}>{busyRequestId === request.requestId ? "Guardando..." : "Aceptar"}</button>
              </div>
            </article>
          ))}</div>
        ) : <p>No hay solicitudes pendientes.</p>}
      </section>
    </div>
  );
}
