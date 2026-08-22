"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import {
  refereeArray,
  refereeDateLabel,
  refereeModalityLabel,
  refereeModalities,
  refereeNumber,
  refereeRecord,
  refereeText,
  refereeWeekdayLabels,
  type RefereeJson,
} from "../referee-platform-contract";
import { supabase } from "../supabaseClient";
import { RefereeProfileCard } from "./referee-profile-card";
import styles from "./referee-platform-client.module.css";

const cachePrefix = "pachangas-referee-platform-read-v1";
const cacheVersion = 1;

function cacheKey(userId: string) { return `${cachePrefix}:${userId}`; }
function input(form: FormData, key: string) { return String(form.get(key) ?? "").trim(); }
function localDateTimeInput(value: unknown) {
  const date = new Date(refereeText(value));
  if (Number.isNaN(date.getTime())) return "";
  const part = (number: number) => String(number).padStart(2, "0");
  return `${date.getFullYear()}-${part(date.getMonth() + 1)}-${part(date.getDate())}T${part(date.getHours())}:${part(date.getMinutes())}`;
}

function readCache(userId: string) {
  try {
    const envelope = refereeRecord(JSON.parse(window.localStorage.getItem(cacheKey(userId)) ?? "null"));
    return refereeNumber(envelope.version) === cacheVersion ? refereeRecord(envelope.data) : null;
  } catch { return null; }
}

function writeCache(userId: string, data: RefereeJson) {
  try { window.localStorage.setItem(cacheKey(userId), JSON.stringify({ data, storedAt: new Date().toISOString(), version: cacheVersion })); } catch { /* Read cache is optional. */ }
}

function Badge({ value }: { value: unknown }) {
  return <span className={styles.badge} data-status={refereeText(value)}>{refereeText(value).replaceAll("_", " ") || "sin estado"}</span>;
}

export function RefereePlatformClient({ laboratory = false }: { laboratory?: boolean }) {
  const [data, setData] = useState<RefereeJson | null>(null);
  const [userId, setUserId] = useState("");
  const [accessToken, setAccessToken] = useState("");
  const [loading, setLoading] = useState(Boolean(supabase));
  const [busy, setBusy] = useState(false);
  const [cached, setCached] = useState(false);
  const [message, setMessage] = useState(supabase ? "" : "Supabase no está configurado.");
  const [availabilityWindowRows, setAvailabilityWindowRows] = useState(3);
  const [availabilityExceptionRows, setAvailabilityExceptionRows] = useState(2);
  const [oneTimeToken, setOneTimeToken] = useState<{ id: string; token: string } | null>(null);
  const [externalInvitation, setExternalInvitation] = useState({ id: "", token: "" });
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (actorId: string, token: string, reason: "initial" | "manual" | "mutation" | "realtime" = "manual") => {
    try {
      const response = await fetch("/api/referees/me", { cache: "no-store", headers: { Authorization: `Bearer ${token}` } });
      const body = await response.json() as RefereeJson & { message?: string };
      if (!response.ok) throw new Error(body.message || "No se pudo recuperar la ficha arbitral.");
      const canonical = refereeRecord(body);
      setData(canonical);
      setCached(false);
      writeCache(actorId, canonical);
      if (reason === "realtime") setMessage("Estado arbitral actualizado.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar la ficha arbitral.");
    } finally { setLoading(false); }
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
      if (!actorId || !token) { setLoading(false); setMessage("Inicia sesión para gestionar tu ficha de árbitro."); return; }
      setUserId(actorId);
      setAccessToken(token);
      const hash = new URLSearchParams(window.location.hash.slice(1));
      setExternalInvitation({ id: hash.get("relationship") ?? "", token: hash.get("token") ?? "" });
      const local = readCache(actorId);
      if (local) { setData(local); setCached(true); setLoading(false); }
      void loadCanonical(actorId, token, "initial");
      channel = client.channel(`referee-platform:${actorId}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_referee_invalidations" }, () => {
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(actorId, token, "realtime"), 120);
        })
        .subscribe();
    });
    return () => {
      active = false;
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel) void client.removeChannel(channel);
    };
  }, [loadCanonical]);

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: RefereeJson) {
    if (!accessToken || !userId) return;
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Enviando intención al servidor...");
    setOneTimeToken(null);
    try {
      const response = await clientWriteFetch("api:referee-command", "/api/referees/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as { canonical?: RefereeJson; message?: string };
      if (!response.ok) throw new Error(body.message || "Operación no confirmada.");
      const canonical = refereeRecord(body.canonical);
      const token = refereeText(canonical.oneTimeToken);
      const relationshipId = refereeText(refereeRecord(canonical.snapshot).relationship)
        || refereeText(refereeRecord(refereeRecord(canonical.snapshot).relationship).id)
        || aggregateId;
      if (token) setOneTimeToken({ id: relationshipId, token });
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await loadCanonical(userId, accessToken, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Se ha recargado el estado canónico." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(userId, accessToken, "manual");
    } finally { setBusy(false); }
  }

  async function adminCommand(action: string, aggregateId: string, expectedRevision: number, payload: RefereeJson) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Enviando operación administrativa...");
    try {
      const response = await clientWriteFetch("api:platform-admin-referees", "/api/platform-admin/referees", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        method: "POST",
      });
      const body = await response.json() as { message?: string };
      if (!response.ok) throw new Error(body.message || "Operación administrativa no confirmada.");
      pending.current = null;
      setMessage("Operación administrativa confirmada.");
      await loadCanonical(userId, accessToken, "mutation");
    } catch (error) { setMessage(error instanceof Error ? error.message : "Operación administrativa no confirmada."); }
    finally { setBusy(false); }
  }

  const privateProfile = refereeRecord(data?.profile);
  const profile = refereeRecord(privateProfile.profile);
  const flags = refereeRecord(data?.flags);
  const pendingInvitations = refereeArray(data?.pendingInvitations);
  const modalities = refereeArray(privateProfile.modalities).filter((item) => item.active === true);
  const areas = refereeArray(privateProfile.areas).filter((item) => refereeText(item.status) === "active");
  const windows = refereeArray(privateProfile.availabilityWindows).filter((item) => refereeText(item.status) === "active");
  const exceptions = refereeArray(privateProfile.availabilityExceptions).filter((item) => refereeText(item.status) === "active");
  const relationships = refereeArray(privateProfile.relationships);
  const assignments = refereeArray(privateProfile.assignments);
  const statistics = refereeRecord(privateProfile.statistics);
  const profileId = refereeText(profile.id);
  const profileRevision = refereeNumber(profile.revision);
  const cardProfile = { ...profile, areas, clubs: relationships.filter((item) => refereeText(item.status) === "active"), modalities, statistics };
  const renderedWindowRows = Math.max(availabilityWindowRows, windows.length, 1);
  const renderedExceptionRows = Math.max(availabilityExceptionRows, exceptions.length, 1);

  function createProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("profile.create", crypto.randomUUID(), 0, {
      availabilityStatus: input(form, "availabilityStatus"), bio: input(form, "bio"),
      experienceSinceYear: input(form, "experienceSinceYear"), experienceSummary: input(form, "experienceSummary"),
      reason: "referee_profile_create", slug: input(form, "slug"),
    });
  }

  function updateProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("profile.update", profileId, profileRevision, {
      availabilityStatus: input(form, "availabilityStatus"), availableForAssignments: form.get("availableForAssignments") === "on",
      bio: input(form, "bio"), experienceSinceYear: input(form, "experienceSinceYear"),
      experienceSummary: input(form, "experienceSummary"), reason: "referee_profile_update",
      shareRecurringAvailability: form.get("shareRecurringAvailability") === "on", slug: input(form, "slug"),
      visibility: input(form, "visibility"),
    });
  }

  function updateModalities(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("profile.modalities.replace", profileId, profileRevision, {
      modalities: refereeModalities.filter((modality) => form.get(modality) === "on").map((modality) => ({ modality })),
      reason: "referee_modalities_replace",
    });
  }

  function updateAreas(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const nextAreas = [1, 2, 3].map((index) => ({
      countryCode: input(form, `country${index}`) || "ES", generalArea: input(form, `area${index}`),
      municipality: input(form, `municipality${index}`), province: input(form, `province${index}`),
      travelRadiusKm: input(form, `radius${index}`),
    })).filter((area) => area.generalArea);
    void command("profile.areas.replace", profileId, profileRevision, { areas: nextAreas, reason: "referee_areas_replace" });
  }

  function updateAvailability(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const nextWindows = Array.from({ length: renderedWindowRows }, (_, index) => {
      const suffix = index + 1;
      return {
        endLocalTime: input(form, `endLocalTime${suffix}`),
        publicVisible: form.get(`publicVisible${suffix}`) === "on",
        startLocalTime: input(form, `startLocalTime${suffix}`),
        timezone: input(form, `timezone${suffix}`) || "Europe/Madrid",
        weekday: input(form, `weekday${suffix}`),
      };
    });
    const nextExceptions = Array.from({ length: renderedExceptionRows }, (_, index) => {
      const suffix = index + 1;
      return {
        reason: input(form, `exceptionReason${suffix}`),
        unavailableFrom: input(form, `unavailableFrom${suffix}`),
        unavailableUntil: input(form, `unavailableUntil${suffix}`),
      };
    });
    if (nextWindows.some((window) => Boolean(window.startLocalTime) !== Boolean(window.endLocalTime))) {
      setMessage("Completa las dos horas de cada ventana semanal.");
      return;
    }
    if (nextExceptions.some((exception) => Boolean(exception.unavailableFrom) !== Boolean(exception.unavailableUntil))) {
      setMessage("Completa el inicio y el final de cada excepción.");
      return;
    }
    void command("profile.availability.replace", profileId, profileRevision, {
      exceptions: nextExceptions.filter((exception) => exception.unavailableFrom && exception.unavailableUntil),
      reason: "referee_availability_replace",
      windows: nextWindows.filter((window) => window.startLocalTime && window.endLocalTime),
    });
  }

  function relationshipRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("relationship.request", crypto.randomUUID(), 0, {
      clubId: input(form, "clubId"), reason: "referee_club_request", relationshipType: input(form, "relationshipType"),
    });
  }

  function relationshipInvite(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const targetKind = input(form, "targetKind");
    void command("relationship.invite", crypto.randomUUID(), 0, {
      clubId: input(form, "clubId"), expiresAt: input(form, "expiresAt"), reason: "club_referee_invite",
      relationshipType: input(form, "relationshipType"), targetEmail: targetKind === "email_target" ? input(form, "target") : "",
      targetKind, targetUserId: targetKind === "registered_user" ? input(form, "target") : "",
    });
  }

  function assignmentPropose(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("assignment.propose", crypto.randomUUID(), 0, {
      assignmentRole: "MAIN_REFEREE", message: input(form, "message"), reason: "referee_assignment_propose",
      refereeProfileId: input(form, "refereeProfileId"), requesterId: input(form, "requesterId"),
      requesterKind: input(form, "requesterKind"), responseDeadline: input(form, "responseDeadline"),
      sourceGroupId: input(form, "sourceGroupId"), sourceId: input(form, "sourceId"), sourceKind: input(form, "sourceKind"),
    });
  }

  function assignmentReplace(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("assignment.replace", input(form, "assignmentId"), Number(input(form, "revision")), {
      message: input(form, "message"), newAssignmentId: crypto.randomUUID(), newRefereeProfileId: input(form, "newRefereeProfileId"),
      reason: "referee_assignment_replace", responseDeadline: input(form, "responseDeadline"),
    });
  }

  if (loading && !data) return <main className={styles.page}><p className={styles.empty}>Cargando plataforma arbitral...</p></main>;

  return (
    <main className={styles.page} data-laboratory={laboratory || undefined}>
      <header className={styles.header}>
        <div><p>{laboratory ? "Laboratorio R3" : "Perfil"}</p><h1>{laboratory ? "Referee Platform" : "Mi ficha de árbitro"}</h1><span>{cached ? "Caché local · actualizando" : "Servidor canónico"}</span></div>
        <div><button type="button" disabled={!userId || busy} onClick={() => void loadCanonical(userId, accessToken, "manual")}>Actualizar</button><Link href={laboratory ? "/admin/referees" : "/"}>Volver</Link></div>
      </header>

      {message ? <p className={styles.message} role="status">{message}</p> : null}
      {oneTimeToken ? <section className={styles.secret}><strong>Enlace de un solo uso</strong><code>{`${window.location.origin}/perfil/arbitro#relationship=${oneTimeToken.id}&token=${oneTimeToken.token}`}</code></section> : null}
      {laboratory ? <section className={styles.flags}>{Object.entries(flags).filter(([key]) => key.endsWith("Enabled")).map(([key, value]) => <span key={key}>{key.replace("Enabled", "")} <strong>{value ? "ON" : "OFF"}</strong></span>)}</section> : null}

      {!profileId ? (
        <section className={styles.singlePanel}>
          <h2>Crear ficha de árbitro</h2>
          <form className={styles.formGrid} onSubmit={createProfile}>
            <label>Slug<input name="slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="nombre-arbitro" /></label>
            <label>Disponibilidad<select name="availabilityStatus" defaultValue="UNAVAILABLE"><option value="AVAILABLE">Disponible</option><option value="LIMITED">Limitada</option><option value="UNAVAILABLE">No disponible</option></select></label>
            <label>Año de inicio<input name="experienceSinceYear" type="number" min="1950" max={new Date().getFullYear()} /></label>
            <label className={styles.wide}>Bio<textarea name="bio" rows={3} maxLength={1200} required /></label>
            <label className={styles.wide}>Experiencia<textarea name="experienceSummary" rows={3} maxLength={1200} /></label>
            <button type="submit" disabled={busy || !flags.selfServiceEnabled}>Crear ficha</button>
          </form>
          {!flags.selfServiceEnabled ? <p className={styles.empty}>El alta arbitral está cerrada en este entorno.</p> : null}
        </section>
      ) : (
        <div className={styles.layout}>
          <aside className={styles.cardColumn}>
            <RefereeProfileCard profile={cardProfile} />
            <div className={styles.statusRow}><Badge value={profile.operationalStatus} /><Badge value={profile.verificationStatus} /><Badge value={profile.marketplaceStatus} /></div>
            {refereeText(profile.visibility) === "public" && refereeText(profile.operationalStatus) === "active" ? <Link className={styles.publicLink} href={`/arbitros/${refereeText(profile.slug)}`}>Ver perfil público</Link> : null}
          </aside>

          <div className={styles.content}>
            <section className={styles.panel}><h2>Identidad arbitral</h2><form className={styles.formGrid} onSubmit={updateProfile}>
              <label>Slug<input name="slug" defaultValue={refereeText(profile.slug)} required /></label>
              <label>Visibilidad<select name="visibility" defaultValue={refereeText(profile.visibility)}><option value="private">Privado</option><option value="unlisted">No listado</option><option value="public">Público</option></select></label>
              <label>Disponibilidad<select name="availabilityStatus" defaultValue={refereeText(profile.availabilityStatus)}><option value="AVAILABLE">Disponible</option><option value="LIMITED">Limitada</option><option value="UNAVAILABLE">No disponible</option></select></label>
              <label>Año de inicio<input name="experienceSinceYear" type="number" defaultValue={refereeText(profile.experienceSinceYear)} /></label>
              <label className={styles.wide}>Bio<textarea name="bio" rows={3} defaultValue={refereeText(profile.bio)} /></label>
              <label className={styles.wide}>Experiencia<textarea name="experienceSummary" rows={3} defaultValue={refereeText(profile.experienceSummary)} /></label>
              <label className={styles.check}><input name="availableForAssignments" type="checkbox" defaultChecked={profile.availableForAssignments === true} />Acepto propuestas</label>
              <label className={styles.check}><input name="shareRecurringAvailability" type="checkbox" defaultChecked={profile.shareRecurringAvailability === true} />Publicar ventanas generales</label>
              <button type="submit" disabled={busy}>Guardar perfil</button>
            </form><div className={styles.actions}>
              {refereeText(profile.operationalStatus) === "draft" ? <button type="button" disabled={busy} onClick={() => void command("profile.activate", profileId, profileRevision, { reason: "referee_profile_activate" })}>Activar</button> : null}
              {refereeText(profile.operationalStatus) === "active" && refereeText(profile.marketplaceStatus) !== "listed" ? <button type="button" disabled={busy} onClick={() => void command("marketplace.list", profileId, profileRevision, { reason: "referee_marketplace_list" })}>Publicar en Mercado</button> : null}
              {refereeText(profile.marketplaceStatus) === "listed" ? <button type="button" disabled={busy} onClick={() => void command("marketplace.pause", profileId, profileRevision, { reason: "referee_marketplace_pause" })}>Pausar Mercado</button> : null}
              {refereeText(profile.marketplaceStatus) === "paused" ? <button type="button" disabled={busy} onClick={() => void command("marketplace.list", profileId, profileRevision, { reason: "referee_marketplace_resume" })}>Reanudar Mercado</button> : null}
            </div></section>

            <section className={styles.panel}><h2>Modalidades</h2><form className={styles.checkGrid} onSubmit={updateModalities}>{refereeModalities.map((modality) => <label key={modality}><input type="checkbox" name={modality} defaultChecked={modalities.some((item) => refereeText(item.modality) === modality)} />{refereeModalityLabel(modality)}</label>)}<button type="submit" disabled={busy}>Guardar modalidades</button></form></section>

            <section className={styles.panel}><h2>Zonas de servicio</h2><form className={styles.areaGrid} onSubmit={updateAreas}>{[0, 1, 2].map((index) => { const area = areas[index] ?? {}; const suffix = index + 1; return <div key={suffix}><label>Zona<input name={`area${suffix}`} defaultValue={refereeText(area.generalArea)} placeholder="Barcelona" /></label><label>Municipio<input name={`municipality${suffix}`} defaultValue={refereeText(area.municipality)} /></label><label>Provincia<input name={`province${suffix}`} defaultValue={refereeText(area.province)} /></label><label>Radio km<input name={`radius${suffix}`} type="number" min="0" max="500" defaultValue={refereeText(area.travelRadiusKm)} /></label><input name={`country${suffix}`} type="hidden" value={refereeText(area.countryCode) || "ES"} /></div>; })}<button type="submit" disabled={busy}>Guardar zonas</button></form></section>

            <section className={styles.panel}><h2>Disponibilidad</h2><form key={`availability-${profileRevision}`} className={styles.availabilityForm} onSubmit={updateAvailability}>
              <div className={styles.availabilityGroup}><h3>Ventanas semanales</h3>{Array.from({ length: renderedWindowRows }, (_, index) => { const window = windows[index] ?? {}; const suffix = index + 1; return <div className={styles.availabilityRow} key={`window-${refereeText(window.id) || suffix}`}><label>Día<select name={`weekday${suffix}`} defaultValue={refereeText(window.weekday) || "6"}>{refereeWeekdayLabels.map((label, dayIndex) => <option key={label} value={dayIndex + 1}>{label}</option>)}</select></label><label>Desde<input name={`startLocalTime${suffix}`} type="time" defaultValue={refereeText(window.startLocalTime).slice(0, 5) || (index === 0 ? "16:00" : "")} /></label><label>Hasta<input name={`endLocalTime${suffix}`} type="time" defaultValue={refereeText(window.endLocalTime).slice(0, 5) || (index === 0 ? "21:00" : "")} /></label><label>Zona horaria<input name={`timezone${suffix}`} defaultValue={refereeText(window.timezone) || "Europe/Madrid"} /></label><label className={styles.check}><input name={`publicVisible${suffix}`} type="checkbox" defaultChecked={window.publicVisible === true} />Visible</label></div>; })}<button type="button" disabled={busy || renderedWindowRows >= 40} onClick={() => setAvailabilityWindowRows((count) => Math.min(40, Math.max(count, windows.length) + 1))}>Añadir ventana</button></div>
              <div className={styles.availabilityGroup}><h3>Excepciones privadas</h3>{Array.from({ length: renderedExceptionRows }, (_, index) => { const exception = exceptions[index] ?? {}; const suffix = index + 1; return <div className={styles.exceptionRow} key={`exception-${refereeText(exception.id) || suffix}`}><label>Desde<input name={`unavailableFrom${suffix}`} type="datetime-local" defaultValue={localDateTimeInput(exception.unavailableFrom)} /></label><label>Hasta<input name={`unavailableUntil${suffix}`} type="datetime-local" defaultValue={localDateTimeInput(exception.unavailableUntil)} /></label><label>Motivo privado<input name={`exceptionReason${suffix}`} maxLength={500} defaultValue={refereeText(exception.reason)} /></label></div>; })}<button type="button" disabled={busy || renderedExceptionRows >= 40} onClick={() => setAvailabilityExceptionRows((count) => Math.min(40, Math.max(count, exceptions.length) + 1))}>Añadir excepción</button></div>
              <button type="submit" disabled={busy}>Guardar disponibilidad</button>
            </form></section>

            <section className={styles.panel}><h2>Clubs</h2><form className={styles.inlineForm} onSubmit={relationshipRequest}><label>Club ID<input name="clubId" required /></label><label>Relación<select name="relationshipType" defaultValue="REGULAR"><option value="REGULAR">Regular</option><option value="COLLABORATOR">Colaborador</option><option value="PREFERRED">Preferente</option></select></label><button type="submit" disabled={busy}>Solicitar vinculación</button></form><div className={styles.rows}>{pendingInvitations.map((item) => <article key={refereeText(item.id)}><span><strong>{refereeText(item.clubName)}</strong><small>Invitación · caduca {refereeDateLabel(item.expiresAt)}</small></span><div><button type="button" disabled={busy} onClick={() => void command("relationship.accept", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_relationship_accept", token: externalInvitation.id === refereeText(item.id) ? externalInvitation.token : "" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("relationship.reject", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_relationship_reject", token: externalInvitation.id === refereeText(item.id) ? externalInvitation.token : "" })}>Rechazar</button></div></article>)}{relationships.map((item) => <article key={refereeText(item.id)}><span><strong>{refereeText(item.clubName)}</strong><small>{refereeText(item.relationshipType)} · {refereeText(item.initiatedBy)}</small></span><div><Badge value={item.status} />{refereeText(item.status) === "active" ? <><button type="button" disabled={busy} onClick={() => void command("relationship.visibility.set", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_relationship_visibility", side: "referee", visible: item.showOnRefereeProfile !== true })}>{item.showOnRefereeProfile === true ? "Ocultar" : "Mostrar"}</button><button type="button" disabled={busy} onClick={() => void command("relationship.end", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_relationship_end" })}>Finalizar</button></> : null}</div></article>)}</div></section>

            <section className={styles.panel}><h2>Asignaciones</h2><div className={styles.rows}>{assignments.map((item) => <article key={refereeText(item.id)}><span><strong>{refereeText(item.assignmentRole).replaceAll("_", " ")}</strong><small>{refereeDateLabel(item.scheduledStart)} · {refereeText(item.sourceKind)}</small></span><div><Badge value={item.status} />{refereeText(item.status) === "proposed" ? <><button type="button" disabled={busy} onClick={() => void command("assignment.accept", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_assignment_accept" })}>Aceptar</button><button type="button" disabled={busy} onClick={() => void command("assignment.decline", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_assignment_decline" })}>Rechazar</button></> : null}{new Set(["accepted", "confirmed"]).has(refereeText(item.status)) ? <button type="button" disabled={busy} onClick={() => void command("assignment.cancel", refereeText(item.id), refereeNumber(item.revision), { reason: "referee_assignment_cancel", reasonCode: "referee_cancelled", reasonText: "Cancelado por el árbitro" })}>Cancelar</button> : null}{laboratory && refereeText(item.status) === "confirmed" ? <button type="button" disabled={busy} onClick={() => void adminCommand("assignment.reconcile", refereeText(item.id), refereeNumber(item.revision), { reason: "staging_manual_reconcile" })}>Reconciliar</button> : null}</div></article>)}{!assignments.length ? <p className={styles.empty}>Sin asignaciones.</p> : null}</div></section>

            {laboratory ? <section className={styles.labGrid}>
              <div className={styles.panel}><h2>Club invita</h2><form className={styles.formGrid} onSubmit={relationshipInvite}><label>Club ID<input name="clubId" required /></label><label>Destino<select name="targetKind" defaultValue="registered_user"><option value="registered_user">Usuario</option><option value="email_target">Email</option></select></label><label className={styles.wide}>Usuario UUID o email<input name="target" required /></label><label>Relación<select name="relationshipType" defaultValue="REGULAR"><option value="REGULAR">Regular</option><option value="COLLABORATOR">Colaborador</option><option value="PREFERRED">Preferente</option></select></label><label>Caduca<input name="expiresAt" type="datetime-local" /></label><button type="submit" disabled={busy}>Invitar</button></form></div>
              <div className={styles.panel}><h2>Proponer partido</h2><form className={styles.formGrid} onSubmit={assignmentPropose}><label>Árbitro profile ID<input name="refereeProfileId" required /></label><label>Autoridad<select name="requesterKind"><option value="TEAM">Team</option><option value="CLUB">Club</option></select></label><label>Requester ID<input name="requesterId" required /></label><label>Source kind<input name="sourceKind" defaultValue="group_match" required /></label><label>Source group ID<input name="sourceGroupId" /></label><label>Source ID<input name="sourceId" required /></label><label>Deadline<input name="responseDeadline" type="datetime-local" /></label><label className={styles.wide}>Mensaje<input name="message" maxLength={800} /></label><button type="submit" disabled={busy}>Proponer</button></form></div>
              <div className={styles.panel}><h2>Reemplazar árbitro</h2><form className={styles.formGrid} onSubmit={assignmentReplace}><label>Assignment ID<input name="assignmentId" required /></label><label>Revisión<input name="revision" type="number" min="1" required /></label><label>Nuevo profile ID<input name="newRefereeProfileId" required /></label><label>Deadline<input name="responseDeadline" type="datetime-local" /></label><label className={styles.wide}>Mensaje<input name="message" maxLength={800} /></label><button type="submit" disabled={busy}>Proponer reemplazo</button></form></div>
            </section> : null}
          </div>
        </div>
      )}
    </main>
  );
}
