"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import styles from "./page.module.css";

type JsonRecord = Record<string, unknown>;
const cachePrefix = "pachangas-club-foundation-read-v1";
const cacheVersion = 1;

function record(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function array(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function text(value: unknown) { return typeof value === "string" ? value : ""; }
function number(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function input(form: FormData, key: string) { return String(form.get(key) ?? "").trim(); }
function dateLabel(value: unknown) { if (typeof value !== "string") return "Sin fecha"; const date = new Date(value); return Number.isNaN(date.getTime()) ? "Sin fecha" : date.toLocaleString("es-ES", { dateStyle: "medium", timeStyle: "short" }); }
function cacheKey(userId: string) { return `${cachePrefix}:${userId}`; }

function readCache(userId: string) {
  try {
    const envelope = record(JSON.parse(window.localStorage.getItem(cacheKey(userId)) ?? "null"));
    return number(envelope.version) === cacheVersion ? record(envelope.data) : null;
  } catch { return null; }
}

function writeCache(userId: string, data: JsonRecord) {
  try { window.localStorage.setItem(cacheKey(userId), JSON.stringify({ data, storedAt: new Date().toISOString(), version: cacheVersion })); } catch { /* Optional read cache. */ }
}

function Status({ children }: { children: string }) {
  return <span className={styles.status} data-status={children}>{children.replaceAll("_", " ")}</span>;
}

export default function ClubFoundationLabPage() {
  const [data, setData] = useState<JsonRecord | null>(null);
  const [userId, setUserId] = useState("");
  const [accessToken, setAccessToken] = useState("");
  const [selectedClubId, setSelectedClubId] = useState("");
  const [loading, setLoading] = useState(Boolean(supabase));
  const [busy, setBusy] = useState(false);
  const [cached, setCached] = useState(false);
  const [message, setMessage] = useState("");
  const [oneTimeInvitation, setOneTimeInvitation] = useState<{ id: string; token: string } | null>(null);
  const [invitationTokens, setInvitationTokens] = useState<Record<string, string>>({});
  const [externalInvitationId, setExternalInvitationId] = useState("");
  const [externalInvitationToken, setExternalInvitationToken] = useState("");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (actorId: string, reason: "initial" | "mutation" | "realtime" | "manual" = "manual") => {
    if (!supabase) { setLoading(false); setMessage("Supabase no está configurado."); return; }
    const result = await supabase.rpc("get_my_pachanga_club_foundation_v1");
    if (result.error) { setLoading(false); setMessage(result.error.message); return; }
    const canonical = record(result.data);
    setData(canonical);
    setCached(false);
    writeCache(actorId, canonical);
    setLoading(false);
    if (reason === "realtime") setMessage("Vista canónica actualizada.");
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
      if (!actorId || !token) { setLoading(false); setMessage("Inicia sesión para abrir el laboratorio."); return; }
      setUserId(actorId);
      setAccessToken(token);
      const sharedInvitation = new URLSearchParams(window.location.hash.slice(1));
      setExternalInvitationId(sharedInvitation.get("invitation") ?? "");
      setExternalInvitationToken(sharedInvitation.get("token") ?? "");
      const local = readCache(actorId);
      if (local) { setData(local); setCached(true); setLoading(false); }
      void loadCanonical(actorId, "initial");
      channel = client.channel(`club-foundation:${actorId}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_club_invalidations" }, () => {
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(actorId, "realtime"), 120);
        })
        .subscribe();
    });
    return () => {
      active = false;
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel) void client.removeChannel(channel);
    };
  }, [loadCanonical]);

  const flags = record(data?.flags);
  const clubs = useMemo(() => array(data?.clubs), [data]);
  const pendingInvitations = useMemo(() => array(data?.pendingInvitations), [data]);
  const selected = useMemo(() => clubs.find((item) => text(record(item.club).id) === selectedClubId) ?? clubs[0] ?? null, [clubs, selectedClubId]);
  const club = record(selected?.club);
  const capabilities = record(selected?.capabilities);
  const memberships = array(selected?.memberships);
  const invitations = array(selected?.pendingInvitations);
  const relationships = array(selected?.teamRelationships);
  const competitions = array(selected?.competitions);
  const entitlement = record(selected?.entitlements);
  const grants = array(entitlement.grants);
  const clubId = text(club.id);

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: JsonRecord) {
    if (!accessToken || !userId) return;
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("");
    setOneTimeInvitation(null);
    try {
      const response = await clientWriteFetch("api:club-foundation-command", "/api/clubs/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as { canonical?: JsonRecord; error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada");
      const canonical = record(body.canonical);
      const createdToken = text(canonical.oneTimeToken);
      const createdInvitationId = text(canonical.invitationId);
      if (createdToken && createdInvitationId) setOneTimeInvitation({ id: createdInvitationId, token: createdToken });
      pending.current = null;
      setMessage("Operación confirmada por PostgreSQL.");
      await loadCanonical(userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. La vista canónica se recargará antes de repetir." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(userId, "manual");
    } finally { setBusy(false); }
  }

  function submitCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    const id = crypto.randomUUID();
    void command("club.create", id, 0, {
      clubType: input(form, "clubType"), countryCode: input(form, "countryCode"),
      description: input(form, "description"), generalArea: input(form, "generalArea"),
      municipality: input(form, "municipality"), name: input(form, "name"),
      province: input(form, "province"), reason: "club_create", slug: input(form, "slug"),
      visibility: input(form, "visibility"),
    });
  }

  function submitProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    void command("club.profile.update", clubId, number(club.revision), {
      clubType: input(form, "clubType"), countryCode: input(form, "countryCode"),
      description: input(form, "description"), generalArea: input(form, "generalArea"),
      municipality: input(form, "municipality"), name: input(form, "name"),
      province: input(form, "province"), reason: "club_profile_update", slug: input(form, "slug"),
      visibility: input(form, "visibility"), websiteUrl: input(form, "websiteUrl"),
    });
  }

  function submitInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    const targetKind = input(form, "targetKind");
    void command("membership.invite", clubId, number(club.revision), {
      expiresAt: input(form, "expiresAt"), reason: "club_staff_invitation", role: input(form, "role"),
      targetEmail: targetKind === "email_target" ? input(form, "target") : "",
      targetKind, targetUserId: targetKind === "registered_user" ? input(form, "target") : "",
    });
  }

  function submitRelationship(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    void command("team_relationship.invite", clubId, number(club.revision), {
      groupId: input(form, "groupId"), reason: "club_team_invitation", relationshipType: input(form, "relationshipType"),
    });
  }

  function submitTeamRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    void command("team_relationship.request", input(form, "targetClubId"), Number(input(form, "expectedRevision")), {
      groupId: input(form, "groupId"), reason: "team_club_request", relationshipType: input(form, "relationshipType"),
    });
  }

  function submitOwnerTransfer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    void command("club.primary_owner.transfer", clubId, number(club.revision), {
      reason: "club_primary_owner_transfer",
      retainPreviousOwner: form.get("retainPreviousOwner") === "on",
      targetUserId: input(form, "targetUserId"),
    });
  }

  async function submitExternalInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;
    pending.current = null;
    setBusy(true);
    setMessage("");
    const form = new FormData(event.currentTarget);
    const invitationId = input(form, "invitationId");
    const token = input(form, "token");
    const intent = input(form, "intent");
    const resolved = await supabase.rpc("get_pachanga_club_invitation_v1", {
      invitation_token: token,
      target_invitation_id: invitationId,
    });
    if (resolved.error) {
      setBusy(false);
      setMessage(resolved.error.message);
      return;
    }
    setBusy(false);
    await command(intent === "decline" ? "membership.decline" : "membership.accept", invitationId, number(record(resolved.data).revision), {
      reason: intent === "decline" ? "club_invitation_decline" : "club_invitation_accept",
      token,
    });
  }

  function submitCompetition(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pending.current = null;
    const form = new FormData(event.currentTarget);
    void command("competition.create", clubId, number(entitlement.organizerRevision), {
      competitionType: input(form, "competitionType"), editionName: input(form, "editionName"),
      name: input(form, "name"), reason: "club_competition_create", ruleSetName: "Reglamento principal",
      seasonLabel: input(form, "seasonLabel"), slug: input(form, "slug"), visibility: "private",
    });
  }

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div><p>Laboratorio R2</p><h1>Club Foundation</h1><span>{cached ? "Caché local · actualizando" : "Servidor canónico"}</span></div>
        <div className={styles.headerActions}><button type="button" onClick={() => void loadCanonical(userId, "manual")} disabled={!userId || busy}>Actualizar</button><Link href="/">Volver</Link></div>
      </header>

      {message ? <p className={styles.message} role="status">{message}</p> : null}
      {oneTimeInvitation ? <p className={styles.secret}><strong>Enlace mostrado una sola vez</strong><code>{`${typeof window === "undefined" ? "" : window.location.origin}/laboratorio-club-foundation#invitation=${oneTimeInvitation.id}&token=${oneTimeInvitation.token}`}</code></p> : null}
      {loading && !data ? <p className={styles.empty}>Cargando...</p> : null}

      <section className={styles.flags} aria-label="Flags de Club Foundation">
        <span>Fundación <strong>{flags.foundationEnabled ? "ON" : "OFF"}</strong></span>
        <span>Creación <strong>{flags.selfServiceCreationEnabled ? "ON" : "OFF"}</strong></span>
        <span>Club–Equipo <strong>{flags.teamRelationshipsEnabled ? "ON" : "OFF"}</strong></span>
        <span>Público <strong>{flags.publicProfilesEnabled ? "ON" : "OFF"}</strong></span>
        <span>Organizador <strong>{flags.competitionOrganizerEnabled ? "ON" : "OFF"}</strong></span>
      </section>

      <div className={styles.layout}>
        <aside className={styles.sidebar}>
          <h2>Mis clubes</h2>
          {clubs.map((item) => {
            const itemClub = record(item.club);
            return <button type="button" key={text(itemClub.id)} data-active={text(itemClub.id) === clubId} onClick={() => setSelectedClubId(text(itemClub.id))}><strong>{text(itemClub.name)}</strong><span>{text(itemClub.operationalStatus)}</span></button>;
          })}
          {!clubs.length ? <p>Sin clubes</p> : null}
        </aside>

        <div className={styles.content}>
          <section className={styles.panel}>
            <h2>Crear club</h2>
            <form className={styles.formGrid} onSubmit={submitCreate}>
              <label>Nombre<input name="name" required minLength={3} maxLength={120} /></label>
              <label>Slug<input name="slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" /></label>
              <label>Tipo<select name="clubType" defaultValue="FOOTBALL_CLUB"><option value="FOOTBALL_CLUB">Club de fútbol</option><option value="SPORTS_CENTER">Centro deportivo</option><option value="ASSOCIATION">Asociación</option><option value="INDEPENDENT_ORGANIZER">Organizador independiente</option><option value="OTHER">Otro</option></select></label>
              <label>Visibilidad<select name="visibility" defaultValue="private"><option value="private">Privado</option><option value="unlisted">No listado</option><option value="public">Público</option></select></label>
              <label>Provincia<input name="province" /></label><label>Municipio<input name="municipality" /></label>
              <label>Área<input name="generalArea" /></label><label>País<input name="countryCode" defaultValue="ES" maxLength={2} /></label>
              <label className={styles.wide}>Descripción<textarea name="description" rows={2} maxLength={2000} /></label>
              <button type="submit" disabled={busy || !flags.selfServiceCreationEnabled}>Crear draft</button>
            </form>
          </section>

          {clubId ? (
            <>
              <section className={styles.clubHeader}>
                <div><p>{text(club.clubType).replaceAll("_", " ")}</p><h2>{text(club.name)}</h2><span>{text(club.municipality)} · revisión {number(club.revision)}</span></div>
                <div><Status>{text(club.operationalStatus)}</Status><Status>{text(club.verificationStatus)}</Status><Status>{text(club.partnershipStatus)}</Status><Link className={styles.controlLink} href={`/admin/clubs?club=${clubId}`}>Control Center</Link></div>
              </section>

              <section className={styles.panel}>
                <div className={styles.panelTitle}><h2>Perfil</h2>{capabilities.profileManage ? <button type="button" disabled={busy || !new Set(["draft", "rejected"]).has(text(club.operationalStatus))} onClick={() => void command("club.review.submit", clubId, number(club.revision), { reason: "club_review_submit" })}>Enviar a revisión</button> : null}</div>
                <form className={styles.formGrid} key={clubId} onSubmit={submitProfile}>
                  <label>Nombre<input name="name" defaultValue={text(club.name)} required /></label><label>Slug<input name="slug" defaultValue={text(club.slug)} required /></label>
                  <label>Tipo<select name="clubType" defaultValue={text(club.clubType)}><option value="FOOTBALL_CLUB">Club de fútbol</option><option value="SPORTS_CENTER">Centro deportivo</option><option value="ASSOCIATION">Asociación</option><option value="INDEPENDENT_ORGANIZER">Organizador independiente</option><option value="OTHER">Otro</option></select></label>
                  <label>Visibilidad<select name="visibility" defaultValue={text(club.visibility)}><option value="private">Privado</option><option value="unlisted">No listado</option><option value="public">Público</option></select></label>
                  <label>Provincia<input name="province" defaultValue={text(club.province)} /></label><label>Municipio<input name="municipality" defaultValue={text(club.municipality)} /></label>
                  <label>Área<input name="generalArea" defaultValue={text(club.generalArea)} /></label><label>País<input name="countryCode" defaultValue={text(club.countryCode)} /></label>
                  <label className={styles.wide}>Web<input name="websiteUrl" type="url" defaultValue={text(club.websiteUrl)} /></label><label className={styles.wide}>Descripción<textarea name="description" rows={3} defaultValue={text(club.description)} /></label>
                  <button type="submit" disabled={busy || !capabilities.profileManage}>Guardar perfil</button>
                </form>
              </section>

              <section className={styles.split}>
                <div className={styles.panel}><h2>Invitar staff</h2><form className={styles.stack} onSubmit={submitInvitation}><label>Destino<select name="targetKind" defaultValue="registered_user"><option value="registered_user">Usuario registrado</option><option value="email_target">Correo</option></select></label><label>Usuario UUID o correo<input name="target" required /></label><label>Rol<select name="role" defaultValue="club_viewer"><option value="club_viewer">Viewer</option><option value="club_competition_manager">Competition manager</option><option value="club_admin">Admin</option><option value="club_owner">Owner</option></select></label><label>Caduca<input name="expiresAt" type="datetime-local" /></label><button type="submit" disabled={busy || !capabilities.staffManage}>Invitar</button></form></div>
                <div className={styles.panel}><h2>Vincular equipo</h2><form className={styles.stack} onSubmit={submitRelationship}><label>Group ID<input name="groupId" required /></label><label>Relación<select name="relationshipType" defaultValue="AFFILIATED"><option value="MEMBER">Miembro</option><option value="AFFILIATED">Afiliado</option><option value="HOSTED">Alojado</option></select></label><button type="submit" disabled={busy || !capabilities.teamLinksManage}>Enviar invitación</button></form></div>
              </section>

              {capabilities.ownershipManage ? <section className={styles.panel}><h2>Transferir primary owner</h2><form className={styles.inlineForm} onSubmit={submitOwnerTransfer}><label>Nuevo owner activo<input name="targetUserId" required placeholder="UUID del miembro club_owner" /></label><label className={styles.check}><input name="retainPreviousOwner" type="checkbox" defaultChecked />Conservar al owner anterior</label><button type="submit" disabled={busy}>Transferir</button></form></section> : null}

              <section className={styles.panel}><h2>Staff</h2>{memberships.length ? <div className={styles.rows}>{memberships.map((item) => <article key={text(item.id)}><span><strong>{text(item.role)}</strong><small>{text(item.userId)} · {text(item.status)}</small></span>{text(item.status) === "active" && text(item.userId) !== text(club.primaryOwnerId) ? <button type="button" disabled={busy || !capabilities.staffManage} onClick={() => void command("membership.revoke", text(item.id), number(item.revision), { reason: "club_membership_revoke" })}>Revocar</button> : null}</article>)}</div> : <p className={styles.empty}>Sin staff</p>}</section>

              <section className={styles.panel}><h2>Invitaciones pendientes</h2>{invitations.length ? <div className={styles.rows}>{invitations.map((item) => <article key={text(item.id)}><span><strong>{text(item.role)}</strong><small>{text(item.targetKind)} · {dateLabel(item.expiresAt)}</small></span><button type="button" disabled={busy || !capabilities.staffManage} onClick={() => void command("membership.invitation.revoke", text(item.id), number(item.revision), { reason: "club_invitation_revoke" })}>Revocar</button></article>)}</div> : <p className={styles.empty}>Sin invitaciones</p>}</section>

              <section className={styles.panel}><h2>Equipos</h2>{relationships.length ? <div className={styles.rows}>{relationships.map((item) => <article key={text(item.id)}><span><strong>{text(item.teamName)} · {text(item.relationshipType)}</strong><small>{text(item.status)} · {text(item.initiatedBy)}</small></span><div className={styles.rowActions}>{new Set(["invited", "requested"]).has(text(item.status)) ? <><button type="button" disabled={busy} onClick={() => void command("team_relationship.accept", text(item.id), number(item.revision), { reason: "club_team_accept" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("team_relationship.reject", text(item.id), number(item.revision), { reason: "club_team_reject" })}>Rechazar</button><button type="button" disabled={busy} onClick={() => void command("team_relationship.cancel", text(item.id), number(item.revision), { reason: "club_team_cancel" })}>Cancelar</button></> : null}{text(item.status) === "active" ? <><button type="button" disabled={busy} onClick={() => void command("team_relationship.visibility.set", text(item.id), number(item.revision), { reason: "club_team_visibility", showOnClubProfile: !item.showOnClubProfile })}>{item.showOnClubProfile ? "Ocultar" : "Mostrar"}</button><button type="button" disabled={busy} onClick={() => void command("team_relationship.end", text(item.id), number(item.revision), { reason: "club_team_end" })}>Finalizar</button></> : null}</div></article>)}</div> : <p className={styles.empty}>Sin relaciones</p>}</section>

              <section className={styles.panel}><h2>Organizador de competición</h2><div className={styles.entitlement}><span>Entitlement <strong>{entitlement.canCreate ? "Activo" : "No concedido"}</strong></span><span>Revisión <strong>{number(entitlement.organizerRevision)}</strong></span><span>Grants <strong>{grants.length}</strong></span></div><form className={styles.formGrid} onSubmit={submitCompetition}><label>Nombre<input name="name" required /></label><label>Slug<input name="slug" required /></label><label>Tipo<select name="competitionType" defaultValue="LEAGUE"><option value="LEAGUE">Liga</option><option value="TOURNAMENT">Torneo</option></select></label><label>Edición<input name="editionName" defaultValue="Edición inicial" /></label><label>Temporada<input name="seasonLabel" defaultValue="Temporada inicial" /></label><button type="submit" disabled={busy || !capabilities.competitionCreate || !entitlement.canCreate || !flags.competitionOrganizerEnabled}>Crear draft</button></form>{competitions.length ? <div className={styles.rows}>{competitions.map((item) => <article key={text(item.id)}><span><strong>{text(item.name)}</strong><small>{text(item.type)} · {text(item.status)}</small></span><Status>{text(item.visibility)}</Status></article>)}</div> : null}</section>
            </>
          ) : null}

          <section className={styles.panel}><h2>Solicitar Club como owner de equipo</h2><form className={styles.inlineForm} onSubmit={submitTeamRequest}><label>Club ID<input name="targetClubId" required /></label><label>Revisión conocida<input name="expectedRevision" type="number" min="1" required /></label><label>Group ID<input name="groupId" required /></label><label>Relación<select name="relationshipType" defaultValue="AFFILIATED"><option value="MEMBER">Miembro</option><option value="AFFILIATED">Afiliado</option><option value="HOSTED">Alojado</option></select></label><button type="submit" disabled={busy || !flags.teamRelationshipsEnabled}>Solicitar vínculo</button></form></section>

          <section className={styles.panel}><h2>Abrir invitación compartida</h2><form className={styles.inlineForm} onSubmit={submitExternalInvitation}><label>Invitation ID<input name="invitationId" required value={externalInvitationId} onChange={(event) => setExternalInvitationId(event.target.value)} /></label><label>Token<input name="token" required value={externalInvitationToken} onChange={(event) => setExternalInvitationToken(event.target.value)} /></label><label>Respuesta<select name="intent" defaultValue="accept"><option value="accept">Aceptar</option><option value="decline">Rechazar</option></select></label><button type="submit" disabled={busy}>Confirmar</button></form></section>

          <section className={styles.panel}><h2>Mis invitaciones</h2>{pendingInvitations.length ? <div className={styles.rows}>{pendingInvitations.map((item) => <article key={text(item.id)}><span><strong>{text(item.clubName)} · {text(item.role)}</strong><small>{dateLabel(item.expiresAt)}</small></span><div className={styles.invitationAction}><input aria-label="Token de invitación" value={invitationTokens[text(item.id)] ?? ""} onChange={(event) => setInvitationTokens((current) => ({ ...current, [text(item.id)]: event.target.value }))} placeholder="Token" /><button type="button" disabled={busy} onClick={() => void command("membership.accept", text(item.id), number(item.revision), { reason: "club_invitation_accept", token: invitationTokens[text(item.id)] ?? "" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("membership.decline", text(item.id), number(item.revision), { reason: "club_invitation_decline", token: invitationTokens[text(item.id)] ?? "" })}>Rechazar</button></div></article>)}</div> : <p className={styles.empty}>Sin invitaciones registradas</p>}</section>
        </div>
      </div>
    </main>
  );
}
