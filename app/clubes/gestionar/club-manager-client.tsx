"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { RefereeAssignmentsClient } from "../../_components/referee-assignments-client";
import { GamePageHeader, ProductFeedback, ResponsiveActionBar, SectionHeader, StatusChip } from "../../_components/official-ui-v2-primitives";
import { clientWriteFetch } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import styles from "./club-manager.module.css";

type JsonRecord = Record<string, unknown>;
type ManagerTab = "arbitros" | "equipos" | "perfil" | "staff";

const cachePrefix = "pachangas-clubs-beta-read-v1";
function record(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function array(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function text(value: unknown) { return typeof value === "string" ? value : ""; }
function number(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function input(form: FormData, key: string) { return String(form.get(key) ?? "").trim(); }
function statusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" { const state = text(value).toLowerCase(); if (["active", "accepted", "verified"].includes(state)) return "success"; if (["rejected", "revoked", "suspended", "ended"].includes(state)) return "danger"; if (["pending_review", "invited", "requested"].includes(state)) return "warning"; if (["draft", "unlisted"].includes(state)) return "info"; return "neutral"; }
function userFacingClubError(detail: string) {
  if (/CLUB_PUBLICATION_PAUSE_REQUIRED/.test(detail)) return "Pon el perfil en privado antes de editar su información pública. Después podrás confirmar de nuevo la publicación.";
  if (/CLUB_PUBLICATION_CONSENT_REQUIRED/.test(detail)) return "Confirma la autorización y la veracidad de la información antes de enviarla a revisión o publicarla.";
  if (/CLUB_APPROVAL_REQUIRES_PENDING_REVIEW/.test(detail)) return "El Club debe estar pendiente de revisión antes de que la plataforma pueda aprobarlo.";
  return detail;
}

function readCache(userId: string) {
  try { const envelope = record(JSON.parse(localStorage.getItem(`${cachePrefix}:${userId}`) ?? "null")); return number(envelope.version) === 1 ? record(envelope.data) : null; } catch { return null; }
}
function writeCache(userId: string, data: JsonRecord) { try { localStorage.setItem(`${cachePrefix}:${userId}`, JSON.stringify({ data, storedAt: new Date().toISOString(), version: 1 })); } catch { /* Derived cache is optional. */ } }

export function ClubManagerClient() {
  const [data, setData] = useState<JsonRecord | null>(null);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [selectedClubId, setSelectedClubId] = useState("");
  const [tab, setTab] = useState<ManagerTab>("perfil");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(() => Boolean(supabase));
  const [cached, setCached] = useState(false);
  const [message, setMessage] = useState(() => supabase ? "" : "Supabase no está configurado.");
  const [oneTimeInvitation, setOneTimeInvitation] = useState<{ id: string; kind: "referee" | "staff"; token: string } | null>(null);
  const [externalInvitation, setExternalInvitation] = useState({ id: "", token: "" });
  const [referees, setReferees] = useState<JsonRecord[]>([]);
  const [requestTarget, setRequestTarget] = useState({ id: "", name: "", revision: 0 });
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (actorId: string, token: string, reason: "initial" | "manual" | "mutation" | "realtime" = "manual") => {
    try {
      const response = await fetch("/api/clubs/me", { cache: "no-store", headers: { Authorization: `Bearer ${token}` } });
      const body = await response.json() as JsonRecord & { message?: string };
      if (!response.ok) throw new Error(text(body.message) || "No se pudieron recuperar tus Clubs.");
      setData(body);
      setCached(false);
      writeCache(actorId, body);
      if (reason === "realtime") setMessage("Estado del Club actualizado.");
    } catch (error) { setMessage(error instanceof Error ? error.message : "No se pudieron recuperar tus Clubs."); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(({ data: sessionData }) => {
      if (!active) return;
      const actorId = sessionData.session?.user.id ?? "";
      const token = sessionData.session?.access_token ?? "";
      if (!actorId || !token) { setLoading(false); setMessage("Inicia sesión para crear o gestionar Clubs."); return; }
      setUserId(actorId);
      setAccessToken(token);
      const hash = new URLSearchParams(location.hash.slice(1));
      setExternalInvitation({ id: hash.get("invitation") ?? "", token: hash.get("token") ?? "" });
      const params = new URLSearchParams(location.search);
      const requestedClubId = params.get("club") ?? "";
      const requestedSection = params.get("section") ?? "";
      if (requestedClubId) setSelectedClubId(requestedClubId);
      if (new Set<ManagerTab>(["arbitros", "equipos", "perfil", "staff"]).has(requestedSection as ManagerTab)) {
        setTab(requestedSection as ManagerTab);
      }
      setRequestTarget({ id: params.get("requestClub") ?? "", name: params.get("clubName") ?? "", revision: number(params.get("clubRevision")) });
      const local = readCache(actorId);
      if (local) { setData(local); setCached(true); setLoading(false); }
      void loadCanonical(actorId, token, "initial");
      const reconcileCanonical = (delay = 120) => {
        if (!active) return;
        if (realtimeTimer.current) clearTimeout(realtimeTimer.current);
        realtimeTimer.current = window.setTimeout(() => {
          if (active) void loadCanonical(actorId, token, "realtime");
        }, delay);
      };
      channel = client.channel(`clubs-beta:${actorId}`).on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_club_invalidations" }, () => {
        reconcileCanonical();
      }).subscribe((status) => {
        if (status === "SUBSCRIBED") reconcileCanonical(500);
      });
    });
    return () => { active = false; if (realtimeTimer.current) clearTimeout(realtimeTimer.current); if (channel) void client.removeChannel(channel); };
  }, [loadCanonical]);

  useEffect(() => {
    if (tab !== "arbitros" || !accessToken) return;
    let active = true;
    void fetch("/api/referees/market?page=1&pageSize=60", { cache: "no-store", headers: { Authorization: `Bearer ${accessToken}` } })
      .then(async (response) => response.ok ? response.json() as Promise<JsonRecord> : {})
      .then((body) => { if (active) setReferees(array(record(body).items)); })
      .catch(() => { if (active) setReferees([]); });
    return () => { active = false; };
  }, [accessToken, tab]);

  const flags = record(data?.flags);
  const clubs = useMemo(() => array(data?.clubs), [data]);
  const ownedTeams = useMemo(() => array(data?.ownedTeams), [data]);
  const pendingInvitations = useMemo(() => array(data?.pendingInvitations), [data]);
  const selected = useMemo(() => selectedClubId === "__new__" ? null : clubs.find((item) => text(record(item.club).id) === selectedClubId) ?? clubs[0] ?? null, [clubs, selectedClubId]);
  const club = record(selected?.club);
  const capabilities = record(selected?.capabilities);
  const consent = record(selected?.publicationConsent);
  const memberships = array(selected?.memberships);
  const staffInvitations = array(selected?.pendingInvitations);
  const teamRelationships = array(selected?.teamRelationships);
  const refereeRelationships = array(selected?.refereeRelationships);
  const teamCandidates = useMemo(() => array(selected?.teamCandidates), [selected]);
  const invitableTeams = useMemo(() => {
    const choices = new Map<string, JsonRecord>();
    for (const item of [...ownedTeams, ...teamCandidates]) choices.set(text(item.id), item);
    return [...choices.values()].sort((left, right) => text(left.name).localeCompare(text(right.name), "es"));
  }, [ownedTeams, teamCandidates]);
  const ownedTeamIds = useMemo(() => new Set(ownedTeams.map((item) => text(item.id))), [ownedTeams]);
  const clubId = text(club.id);
  const clubRevision = number(club.revision);

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: JsonRecord) {
    if (!accessToken || !userId) return;
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true); setMessage("Enviando intención al servidor..."); setOneTimeInvitation(null);
    try {
      const response = await clientWriteFetch("api:club-foundation-command", "/api/clubs/command", { body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }), headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, method: "POST" });
      const body = await response.json() as { canonical?: JsonRecord; message?: string; error?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada.");
      const canonical = record(body.canonical);
      if (text(canonical.oneTimeToken)) {
        setOneTimeInvitation({
          id: text(canonical.invitationId) || text(canonical.relationshipId) || text(canonical.aggregateId),
          kind: action === "referee_relationship.invite" ? "referee" : "staff",
          token: text(canonical.oneTimeToken),
        });
      }
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await loadCanonical(userId, accessToken, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Se ha recargado el estado canónico." : userFacingClubError(detail));
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(userId, accessToken, "manual");
    } finally { setBusy(false); }
  }

  function createClub(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("club.create", crypto.randomUUID(), 0, { clubType: input(form, "clubType"), countryCode: "ES", description: input(form, "description"), generalArea: input(form, "generalArea"), municipality: input(form, "municipality"), name: input(form, "name"), province: input(form, "province"), reason: "clubs_beta_create", slug: input(form, "slug"), visibility: "private" }); }
  function updateProfile(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("club.profile.update", clubId, clubRevision, { clubType: input(form, "clubType"), countryCode: "ES", description: input(form, "description"), generalArea: input(form, "generalArea"), municipality: input(form, "municipality"), name: input(form, "name"), province: input(form, "province"), reason: "clubs_beta_profile", slug: input(form, "slug"), visibility: input(form, "visibility"), websiteUrl: input(form, "websiteUrl") }); }
  function consentPublication(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("publication.consent", clubId, clubRevision, { informationCorrect: form.get("informationCorrect") === "on", representationAuthorized: form.get("representationAuthorized") === "on" }); }
  function inviteStaff(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("membership.invite", clubId, clubRevision, { reason: "clubs_beta_staff_invite", role: input(form, "role"), targetEmail: input(form, "email"), targetKind: "email_target" }); }
  function inviteTeam(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("team_relationship.invite", clubId, clubRevision, { groupId: input(form, "groupId"), reason: "clubs_beta_team_invite", relationshipType: input(form, "relationshipType") }); }
  function requestClub(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("team_relationship.request", requestTarget.id, requestTarget.revision, { groupId: input(form, "groupId"), reason: "clubs_beta_team_request", relationshipType: input(form, "relationshipType") }); }
  function inviteReferee(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const form = new FormData(event.currentTarget); void command("referee_relationship.invite", clubId, clubRevision, { refereeProfileId: input(form, "refereeProfileId"), relationshipType: input(form, "relationshipType") }); }

  function teamRelationshipActions(item: JsonRecord) {
    const relationshipId = text(item.id);
    const revision = number(item.revision);
    const status = text(item.status);
    const ownsTeam = ownedTeamIds.has(text(item.groupId));
    const managesClub = capabilities.teamLinksManage === true;
    if (status === "invited") {
      if (ownsTeam) return <><button type="button" disabled={busy} onClick={() => void command("team_relationship.accept", relationshipId, revision, { reason: "clubs_beta_team_accept" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("team_relationship.reject", relationshipId, revision, { reason: "clubs_beta_team_reject" })}>Rechazar</button></>;
      if (managesClub) return <button type="button" disabled={busy} onClick={() => void command("team_relationship.cancel", relationshipId, revision, { reason: "clubs_beta_team_cancel" })}>Cancelar invitación</button>;
    }
    if (status === "requested") {
      if (managesClub) return <><button type="button" disabled={busy} onClick={() => void command("team_relationship.accept", relationshipId, revision, { reason: "clubs_beta_team_accept" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("team_relationship.reject", relationshipId, revision, { reason: "clubs_beta_team_reject" })}>Rechazar</button></>;
      if (ownsTeam) return <button type="button" disabled={busy} onClick={() => void command("team_relationship.cancel", relationshipId, revision, { reason: "clubs_beta_team_cancel" })}>Cancelar solicitud</button>;
    }
    if (status === "active") return <>{ownsTeam ? <button type="button" disabled={busy} onClick={() => void command("team_relationship.visibility.set", relationshipId, revision, { reason: "clubs_beta_team_visibility", showOnClubProfile: item.showOnClubProfile !== true })}>{item.showOnClubProfile ? "Ocultar" : "Mostrar"}</button> : null}{managesClub || ownsTeam ? <button type="button" disabled={busy} onClick={() => void command("team_relationship.end", relationshipId, revision, { reason: "clubs_beta_team_end" })}>Finalizar</button> : null}</>;
    return null;
  }

  function refereeRelationshipActions(item: JsonRecord) {
    const relationshipId = text(item.id);
    const revision = number(item.revision);
    const status = text(item.status);
    if (capabilities.refereeManage !== true) return null;
    if (status === "requested") return <><button type="button" disabled={busy} onClick={() => void command("referee_relationship.accept", relationshipId, revision, { reason: "clubs_beta_referee_accept" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("referee_relationship.reject", relationshipId, revision, { reason: "clubs_beta_referee_reject" })}>Rechazar</button></>;
    if (status === "invited") return <button type="button" disabled={busy} onClick={() => void command("referee_relationship.cancel", relationshipId, revision, { reason: "clubs_beta_referee_cancel" })}>Cancelar invitación</button>;
    if (status === "active") return <><button type="button" disabled={busy} onClick={() => void command("referee_relationship.visibility.set", relationshipId, revision, { reason: "clubs_beta_referee_visibility", visible: item.showOnClubProfile !== true })}>{item.showOnClubProfile ? "Ocultar" : "Mostrar"}</button><button type="button" disabled={busy} onClick={() => void command("referee_relationship.end", relationshipId, revision, { reason: "clubs_beta_referee_end" })}>Finalizar</button></>;
    return null;
  }

  const context = { detail: cached ? "Caché local · verificando" : clubId ? `Revisión ${clubRevision}` : "Servidor canónico", eyebrow: "Clubs · BETA", status: cached ? "Actualizando" : "En directo", title: text(club.name) || "Mis Clubs" };
  return <OfficialProductShellV2 active="mercado" context={context}><main className={styles.page} data-mobile-tab="mercado">
    <GamePageHeader actions={<><button type="button" disabled={!userId || busy} onClick={() => void loadCanonical(userId, accessToken, "manual")}>Actualizar</button><Link href="/clubes">Directorio</Link></>} eyebrow="BETA" summary="Esta función está en beta. Puedes usarla con normalidad y ayudarnos a mejorarla." title="Gestionar Clubs" />
    {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /no |error|required|requer/i.test(message) ? "danger" : "info"}>{message}</ProductFeedback> : null}
    {oneTimeInvitation ? <ProductFeedback tone="warning"><strong>Enlace mostrado una sola vez:</strong> {oneTimeInvitation.kind === "referee" ? `${location.origin}/perfil/arbitro#relationship=${oneTimeInvitation.id}&token=${oneTimeInvitation.token}` : `${location.origin}/clubes/gestionar#invitation=${oneTimeInvitation.id}&token=${oneTimeInvitation.token}`}</ProductFeedback> : null}
    {loading && !data ? <p className={styles.empty}>Cargando estado canónico...</p> : null}

    <div className={styles.workspace}>
      <aside className={styles.sidebar}><SectionHeader eyebrow="Selección" title="Mis Clubs" />{clubs.map((item) => { const itemClub = record(item.club); return <button aria-current={text(itemClub.id) === clubId ? "page" : undefined} key={text(itemClub.id)} onClick={() => setSelectedClubId(text(itemClub.id))} type="button"><strong>{text(itemClub.name)}</strong><small>{text(itemClub.operationalStatus).replaceAll("_", " ")}</small></button>; })}<button aria-current={!clubId ? "page" : undefined} onClick={() => setSelectedClubId("__new__")} type="button"><strong>Crear Club</strong><small>Nuevo borrador</small></button>{clubId ? <nav>{(["perfil", "staff", "equipos", "arbitros"] as ManagerTab[]).map((item) => <button aria-current={tab === item ? "page" : undefined} key={item} onClick={() => setTab(item)} type="button">{item[0].toUpperCase() + item.slice(1)}</button>)}</nav> : null}</aside>
      <div className={styles.content}>
        {!clubId ? <section className={styles.panel}><SectionHeader eyebrow="Nuevo Club" title="Crear borrador privado" /><form className={styles.formGrid} onSubmit={createClub}><label>Nombre<input name="name" required minLength={3} maxLength={120} /></label><label>Slug<input name="slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" /></label><label>Tipo<select name="clubType" defaultValue="FOOTBALL_CLUB"><option value="FOOTBALL_CLUB">Club de fútbol</option><option value="SPORTS_CENTER">Centro deportivo</option><option value="ASSOCIATION">Asociación</option><option value="INDEPENDENT_ORGANIZER">Organizador</option><option value="OTHER">Otro</option></select></label><label>Provincia<input name="province" /></label><label>Municipio<input name="municipality" /></label><label>Zona general<input name="generalArea" /></label><label className={styles.wide}>Descripción<textarea name="description" rows={3} /></label><button type="submit" disabled={busy || flags.selfServiceCreationEnabled !== true}>Crear Club</button></form></section> : null}

        {requestTarget.id && ownedTeams.length ? <section className={styles.panel}><SectionHeader eyebrow="Equipo → Club" title={`Solicitar vínculo con ${requestTarget.name || "Club"}`} /><form className={styles.inlineForm} onSubmit={requestClub}><label>Mi equipo<select name="groupId">{ownedTeams.map((team) => <option key={text(team.id)} value={text(team.id)}>{text(team.name)}</option>)}</select></label><label>Relación<select name="relationshipType" defaultValue="AFFILIATED"><option value="MEMBER">Miembro</option><option value="AFFILIATED">Afiliado</option><option value="HOSTED">Alojado</option></select></label><button type="submit" disabled={busy || flags.teamRelationshipsEnabled !== true}>Enviar solicitud</button></form></section> : null}

        {clubId && tab === "perfil" ? <><section className={styles.hero}><div><small>{text(club.clubType).replaceAll("_", " ")}</small><h2>{text(club.name)}</h2><p>{text(club.municipality)} · revisión {clubRevision}</p></div><div><StatusChip tone={statusTone(club.operationalStatus)}>{text(club.operationalStatus).replaceAll("_", " ")}</StatusChip><StatusChip tone={statusTone(club.verificationStatus)}>{text(club.verificationStatus) === "verified" ? "Verificado" : "No verificado"}</StatusChip>{text(club.operationalStatus) === "active" && text(club.visibility) === "public" ? <Link href={`/clubes/${text(club.slug)}`}>Ver perfil público</Link> : null}</div></section>
          <section className={styles.panel}><SectionHeader eyebrow="Identidad" title="Perfil del Club" /><form className={styles.formGrid} key={clubId} onSubmit={updateProfile}><label>Nombre<input name="name" defaultValue={text(club.name)} required /></label><label>Slug<input name="slug" defaultValue={text(club.slug)} required /></label><label>Tipo<select name="clubType" defaultValue={text(club.clubType)}><option value="FOOTBALL_CLUB">Club de fútbol</option><option value="SPORTS_CENTER">Centro deportivo</option><option value="ASSOCIATION">Asociación</option><option value="INDEPENDENT_ORGANIZER">Organizador</option><option value="OTHER">Otro</option></select></label><label>Visibilidad<select name="visibility" defaultValue={text(club.visibility)}><option value="private">Privado</option><option value="unlisted">No listado</option><option value="public">Público</option></select></label><label>Provincia<input name="province" defaultValue={text(club.province)} /></label><label>Municipio<input name="municipality" defaultValue={text(club.municipality)} /></label><label>Zona general<input name="generalArea" defaultValue={text(club.generalArea)} /></label><label>Web<input name="websiteUrl" type="url" defaultValue={text(club.websiteUrl)} /></label><label className={styles.wide}>Descripción<textarea name="description" rows={3} defaultValue={text(club.description)} /></label><button type="submit" disabled={busy || capabilities.profileManage !== true}>Guardar perfil</button></form></section>
          <section className={styles.panel}><SectionHeader eyebrow="Publicación" title="Consentimiento y revisión" />{consent.matchesCurrentContent === true ? <ProductFeedback tone="success">Consentimiento vigente para este contenido.</ProductFeedback> : <form className={styles.consent} onSubmit={consentPublication}><label><input name="representationAuthorized" type="checkbox" required />Estoy autorizado para representar este Club u organizador.</label><label><input name="informationCorrect" type="checkbox" required />La información que se publicará es correcta.</label><button type="submit" disabled={busy || capabilities.ownershipManage !== true}>Confirmar publicación</button></form>}<ResponsiveActionBar>{new Set(["draft", "rejected"]).has(text(club.operationalStatus)) ? <button type="button" disabled={busy || consent.matchesCurrentContent !== true || capabilities.profileManage !== true} onClick={() => void command("club.review.submit", clubId, clubRevision, { reason: "clubs_beta_review_submit" })}>Enviar a revisión</button> : null}</ResponsiveActionBar></section></> : null}

        {clubId && tab === "staff" ? <><section className={styles.panel}><SectionHeader eyebrow="Acceso" title="Invitar staff" /><form className={styles.inlineForm} onSubmit={inviteStaff}><label>Correo<input name="email" type="email" required /></label><label>Rol<select name="role" defaultValue="club_viewer"><option value="club_viewer">Viewer</option><option value="club_competition_manager">Competition manager</option><option value="club_admin">Admin</option><option value="club_owner">Owner</option></select></label><button type="submit" disabled={busy || capabilities.staffManage !== true}>Invitar</button></form></section><section className={styles.panel}><SectionHeader eyebrow="Miembros" title="Staff activo" /><div className={styles.rows}>{memberships.map((item) => <article key={text(item.id)}><span><strong>{text(item.role).replaceAll("_", " ")}</strong><small>{text(item.status)}</small></span>{text(item.status) === "active" && text(item.userId) !== text(club.primaryOwnerId) ? <button type="button" disabled={busy || capabilities.staffManage !== true} onClick={() => void command("membership.revoke", text(item.id), number(item.revision), { reason: "clubs_beta_staff_revoke" })}>Revocar</button> : null}</article>)}</div></section><section className={styles.panel}><SectionHeader eyebrow="Pendientes" title="Invitaciones" /><div className={styles.rows}>{staffInvitations.map((item) => <article key={text(item.id)}><span><strong>{text(item.role).replaceAll("_", " ")}</strong><small>Caduca {new Date(text(item.expiresAt)).toLocaleDateString("es-ES")}</small></span><button type="button" disabled={busy || capabilities.staffManage !== true} onClick={() => void command("membership.invitation.revoke", text(item.id), number(item.revision), { reason: "clubs_beta_staff_invite_revoke" })}>Revocar</button></article>)}</div></section></> : null}

        {clubId && tab === "equipos" ? <><section className={styles.panel}><SectionHeader eyebrow="Club → Equipo" title="Invitar equipo público" /><form className={styles.inlineForm} onSubmit={inviteTeam}><label>Equipo<select name="groupId" required><option value="">Selecciona un equipo</option>{invitableTeams.map((team) => <option key={text(team.id)} value={text(team.id)}>{text(team.name)}{text(team.zone) ? ` · ${text(team.zone)}` : ""}</option>)}</select></label><label>Relación<select name="relationshipType" defaultValue="AFFILIATED"><option value="MEMBER">Miembro</option><option value="AFFILIATED">Afiliado</option><option value="HOSTED">Alojado</option></select></label><button type="submit" disabled={busy || capabilities.teamLinksManage !== true || !invitableTeams.length}>Invitar</button></form>{!invitableTeams.length ? <p className={styles.empty}>No hay equipos públicos disponibles para invitar.</p> : null}</section><section className={styles.panel}><SectionHeader eyebrow="Relaciones" title="Equipos vinculados" /><div className={styles.rows}>{teamRelationships.map((item) => <article key={text(item.id)}><span><strong>{text(item.teamName)}</strong><small>{text(item.relationshipType)} · {text(item.status)}</small></span><ResponsiveActionBar>{teamRelationshipActions(item)}</ResponsiveActionBar></article>)}</div></section></> : null}

        {clubId && tab === "arbitros" ? <><section className={styles.panel}><SectionHeader eyebrow="Club → Árbitro" title="Invitar desde Mercado" /><form className={styles.inlineForm} onSubmit={inviteReferee}><label>Árbitro<select name="refereeProfileId" required><option value="">Selecciona una ficha</option>{referees.map((item) => <option key={text(item.refereeProfileId)} value={text(item.refereeProfileId)}>{text(item.displayName)} · {text(item.availabilityStatus).replaceAll("_", " ")}</option>)}</select></label><label>Relación<select name="relationshipType" defaultValue="REGULAR"><option value="REGULAR">Regular</option><option value="COLLABORATOR">Colaborador</option><option value="PREFERRED">Preferente</option></select></label><button type="submit" disabled={busy || capabilities.refereeManage !== true || !referees.length}>Invitar</button></form><Link href="/mercado?tab=arbitros">Abrir Mercado de árbitros</Link></section><section className={styles.panel}><SectionHeader eyebrow="Red arbitral" title="Relaciones" /><div className={styles.rows}>{refereeRelationships.map((item) => <article key={text(item.id)}><span><strong>{text(item.refereeName)}</strong><small>{text(item.relationshipType)} · {text(item.status)}</small></span><ResponsiveActionBar>{refereeRelationshipActions(item)}</ResponsiveActionBar></article>)}</div></section><RefereeAssignmentsClient clubId={clubId} embedded surface="club" /></> : null}

        {pendingInvitations.length || externalInvitation.id ? <section className={styles.panel}><SectionHeader eyebrow="Invitaciones" title="Acceso a Clubs" /><div className={styles.rows}>{pendingInvitations.map((item) => { const hasToken = externalInvitation.id === text(item.id) && Boolean(externalInvitation.token); return <article key={text(item.id)}><span><strong>{text(item.clubName)}</strong><small>{text(item.role).replaceAll("_", " ")}</small></span><ResponsiveActionBar><button type="button" disabled={busy || !hasToken} onClick={() => void command("membership.accept", text(item.id), number(item.revision), { reason: "clubs_beta_invitation_accept", token: hasToken ? externalInvitation.token : "" })}>Aceptar</button><button type="button" disabled={busy || !hasToken} onClick={() => void command("membership.decline", text(item.id), number(item.revision), { reason: "clubs_beta_invitation_decline", token: hasToken ? externalInvitation.token : "" })}>Rechazar</button></ResponsiveActionBar></article>; })}</div></section> : null}
      </div>
    </div>
  </main></OfficialProductShellV2>;
}
