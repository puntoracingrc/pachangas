"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { clientWriteFetch } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import {
  venueArray,
  venueDateTime,
  venueNumber,
  venueRecord,
  venueStatusLabel,
  venueText,
  venueTextArray,
  type VenueJson,
} from "../../venue-operations-contract";
import styles from "../../venue-operations.module.css";

type ClubVenueMode = "reservations" | "venues";

function formText(form: FormData, name: string) {
  return String(form.get(name) ?? "").trim();
}

function localInput(value: unknown) {
  return venueText(value).replace(" ", "T").slice(0, 16);
}

export function ClubVenueOperationsClient({ mode }: { mode: ClubVenueMode }) {
  const [clubsData, setClubsData] = useState<VenueJson | null>(null);
  const [desk, setDesk] = useState<VenueJson | null>(null);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [selectedClubId, setSelectedClubId] = useState("");
  const [selectedVenueId, setSelectedVenueId] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState(supabase ? "" : "Supabase no está configurado.");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);
  const selectedClubIdRef = useRef("");

  const clubs = useMemo(() => venueArray(clubsData?.clubs), [clubsData]);
  const venues = useMemo(() => venueArray(desk?.venues), [desk]);
  const pitches = useMemo(() => venueArray(desk?.pitches), [desk]);
  const templates = useMemo(() => venueArray(desk?.availabilityTemplates), [desk]);
  const exceptions = useMemo(() => venueArray(desk?.availabilityExceptions), [desk]);
  const requests = useMemo(() => venueArray(desk?.requests), [desk]);
  const holds = useMemo(() => venueArray(desk?.holds), [desk]);
  const reservations = useMemo(() => venueArray(desk?.reservations), [desk]);
  const bindings = useMemo(() => venueArray(desk?.matchBindings), [desk]);
  const conflicts = useMemo(() => venueArray(desk?.conflicts), [desk]);
  const selectedVenue = venues.find((venue) => venueText(venue.id) === selectedVenueId) ?? venues[0] ?? {};
  const venuePitches = pitches.filter((pitch) => venueText(pitch.venue_id) === venueText(selectedVenue.id));

  const loadDesk = useCallback(async (clubId: string, token: string, reason: "initial" | "manual" | "mutation" | "realtime") => {
    if (!clubId) {
      setDesk(null);
      setLoading(false);
      return;
    }
    try {
      const response = await fetch("/api/venues/club/" + clubId, { cache: "no-store", headers: { Authorization: "Bearer " + token } });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || "No se pudo recuperar la mesa de Campos.");
      setDesk(body);
      if (reason === "realtime") setMessage("Mesa de Campos actualizada desde el servidor.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar la mesa de Campos.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(async ({ data: sessionData }) => {
      if (!active) return;
      const actorId = sessionData.session?.user.id ?? "";
      const token = sessionData.session?.access_token ?? "";
      if (!actorId || !token) {
        setLoading(false);
        setMessage("Inicia sesión para gestionar Campos del Club.");
        return;
      }
      setUserId(actorId);
      setAccessToken(token);
      const clubsResponse = await fetch("/api/clubs/me", { cache: "no-store", headers: { Authorization: "Bearer " + token } });
      const clubsBody = await clubsResponse.json() as VenueJson;
      if (!active) return;
      if (!clubsResponse.ok) {
        setLoading(false);
        setMessage(venueText(clubsBody.message) || "No se pudieron recuperar tus Clubs.");
        return;
      }
      setClubsData(clubsBody);
      const params = new URLSearchParams(location.search);
      const requestedClub = params.get("club") ?? "";
      const available = venueArray(clubsBody.clubs);
      const initialClub = available.some((item) => venueText(venueRecord(item.club).id) === requestedClub)
        ? requestedClub
        : venueText(venueRecord(available[0]?.club).id);
      setSelectedClubId(initialClub);
      selectedClubIdRef.current = initialClub;
      await loadDesk(initialClub, token, "initial");
      const reconcile = (delay = 120) => {
        if (realtimeTimer.current) clearTimeout(realtimeTimer.current);
        realtimeTimer.current = window.setTimeout(() => {
          const currentClubId = selectedClubIdRef.current;
          if (active && currentClubId) void loadDesk(currentClubId, token, "realtime");
        }, delay);
      };
      channel = client.channel("club-venue-operations:" + initialClub)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_venue_invalidations" }, () => reconcile())
        .subscribe((status) => {
          if (status === "SUBSCRIBED") reconcile(400);
        });
    });
    return () => {
      active = false;
      if (realtimeTimer.current) clearTimeout(realtimeTimer.current);
      if (channel) void client.removeChannel(channel);
    };
  }, [loadDesk]);

  async function changeClub(clubId: string) {
    setSelectedClubId(clubId);
    selectedClubIdRef.current = clubId;
    setLoading(true);
    await loadDesk(clubId, accessToken, "manual");
  }

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: VenueJson) {
    if (!accessToken || !userId || !navigator.onLine) {
      setMessage("Sin conexión: no se ha enviado ningún cambio.");
      return;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Enviando intención al servidor...");
    try {
      const response = await clientWriteFetch("api:venue-operations-command", "/api/venues/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: "Bearer " + accessToken, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || venueText(body.error) || "El servidor rechazó la operación.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await loadDesk(selectedClubId, accessToken, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "La operación no fue confirmada.";
      setMessage(/STALE_REVISION/i.test(detail) ? "La revisión cambió. Se ha recargado el estado canónico." : detail);
      if (/STALE_REVISION/i.test(detail)) await loadDesk(selectedClubId, accessToken, "manual");
    } finally {
      setBusy(false);
    }
  }

  function createVenue(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("venue.create", "", 0, {
      clubId: selectedClubId,
      description: formText(form, "description"),
      generalArea: formText(form, "generalArea"),
      municipality: formText(form, "municipality"),
      name: formText(form, "name"),
      privateAddress: formText(form, "privateAddress"),
      reasonCode: "CLUB_VENUE_CREATE",
      slug: formText(form, "slug").toLowerCase(),
      timezone: formText(form, "timezone") || "Europe/Madrid",
      visibility: "PRIVATE",
    });
  }

  function updateVenue(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("venue.update", venueText(selectedVenue.id), venueNumber(selectedVenue.revision), {
      description: formText(form, "description"),
      generalArea: formText(form, "generalArea"),
      municipality: formText(form, "municipality"),
      name: formText(form, "name"),
      privateAccessInstructions: formText(form, "privateAccessInstructions"),
      privateAddress: formText(form, "privateAddress"),
      privateContactEmail: formText(form, "privateContactEmail"),
      privateContactName: formText(form, "privateContactName"),
      privateContactPhone: formText(form, "privateContactPhone"),
      reasonCode: "CLUB_VENUE_UPDATE",
      slug: formText(form, "slug").toLowerCase(),
      timezone: formText(form, "timezone") || "Europe/Madrid",
      visibility: "PRIVATE",
    });
  }

  function createPitch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("pitch.create", "", 0, {
      bufferMinutes: Number(formText(form, "bufferMinutes") || 0),
      environment: formText(form, "environment"),
      hasChangingRooms: form.get("hasChangingRooms") === "on",
      hasLighting: form.get("hasLighting") === "on",
      hasParking: form.get("hasParking") === "on",
      hasShowers: form.get("hasShowers") === "on",
      isAccessible: form.get("isAccessible") === "on",
      minimumSlotMinutes: Number(formText(form, "minimumSlotMinutes") || 60),
      modalities: form.getAll("modalities").map(String),
      name: formText(form, "name"),
      publicRateCurrency: "EUR",
      publicRateKind: formText(form, "publicRateKind"),
      reasonCode: "CLUB_PITCH_CREATE",
      slug: formText(form, "slug").toLowerCase(),
      surface: formText(form, "surface"),
      venueId: venueText(selectedVenue.id),
      visibility: formText(form, "visibility"),
    });
  }

  function createTemplate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("availability.template.create", "", 0, {
      bufferMinutes: Number(formText(form, "bufferMinutes") || 0),
      capacity: 1,
      endLocalTime: formText(form, "endLocalTime"),
      modalities: [formText(form, "modality")],
      pitchId: formText(form, "pitchId"),
      reasonCode: "CLUB_AVAILABILITY_CREATE",
      slotMinutes: Number(formText(form, "slotMinutes") || 60),
      startLocalTime: formText(form, "startLocalTime"),
      timezone: venueText(selectedVenue.timezone) || "Europe/Madrid",
      validFrom: formText(form, "validFrom"),
      validUntil: formText(form, "validUntil") || null,
      visibility: "PUBLIC",
      weekday: Number(formText(form, "weekday")),
    });
  }

  function createException(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("availability.exception.create", "", 0, {
      endsAt: new Date(formText(form, "endsAt")).toISOString(),
      kind: formText(form, "kind"),
      pitchId: formText(form, "pitchId"),
      priority: Number(formText(form, "priority") || 100),
      privateReason: formText(form, "privateReason"),
      publicReason: formText(form, "publicReason"),
      reasonCode: "CLUB_EXCEPTION_CREATE",
      startsAt: new Date(formText(form, "startsAt")).toISOString(),
      visibility: formText(form, "visibility"),
    });
  }

  function reviewRequest(event: FormEvent<HTMLFormElement>, request: VenueJson, action: "reservation.accept" | "reservation.counter") {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const terms = {
      amountMinor: Math.round(Number(formText(form, "amount")) * 100) || null,
      cancellationTerms: formText(form, "cancellationTerms"),
      currency: "EUR",
      kind: Number(formText(form, "amount")) > 0 ? "FIXED_QUOTE" : "CONTACT_CLUB",
      privateNotes: formText(form, "privateNotes"),
      publicRateAllowed: false,
    };
    void command(action, venueText(request.id), venueNumber(request.revision), {
      localEnd: formText(form, "localEnd"),
      localStart: formText(form, "localStart"),
      message: formText(form, "message"),
      offsetMinutes: venueNumber(request.resolved_offset_minutes),
      pitchId: formText(form, "pitchId") || venueText(request.pitch_id),
      reasonCode: action === "reservation.accept" ? "CLUB_ACCEPT" : "CLUB_COUNTER",
      terms,
      timezone: venueText(request.timezone),
    });
  }

  const context = {
    detail: "Revisión " + venueNumber(desk?.serverSequence),
    eyebrow: "Club · Campos",
    status: "Servidor canónico",
    title: mode === "venues" ? "Campos" : "Reservas",
  };

  const venueView = <div className={styles.content}>
    <section className={styles.surface}><span className={styles.eyebrow}>Inventario</span><h2>Crear instalación privada</h2><form className={styles.formGrid} onSubmit={createVenue}><label>Nombre<input name="name" required maxLength={120} /></label><label>Slug<input name="slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" /></label><label>Municipio<input name="municipality" required /></label><label>Zona general<input name="generalArea" /></label><label>Zona horaria<input name="timezone" defaultValue="Europe/Madrid" required /></label><label>Dirección privada<input name="privateAddress" required /></label><label className={styles.wide}>Descripción<textarea name="description" rows={3} /></label><button className={styles.action} disabled={busy || desk?.canManageVenues !== true} type="submit">Crear Campo</button></form></section>
    {venueText(selectedVenue.id) ? <><section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>{venueStatusLabel(selectedVenue.lifecycle)}</span><h2>{venueText(selectedVenue.name)}</h2></div><div className={styles.actions}>{venueText(selectedVenue.lifecycle) === "DRAFT" ? <><button className={styles.secondaryAction} disabled={busy} onClick={() => void command("venue.submit_review", venueText(selectedVenue.id), venueNumber(selectedVenue.revision), { reasonCode: "CLUB_SUBMIT_REVIEW" })} type="button">Enviar a revisión</button><button className={styles.action} disabled={busy} onClick={() => void command("venue.activate", venueText(selectedVenue.id), venueNumber(selectedVenue.revision), { reasonCode: "CLUB_ACTIVATE" })} type="button">Activar</button></> : null}{venueText(selectedVenue.lifecycle) === "ACTIVE" ? <button className={styles.dangerAction} disabled={busy} onClick={() => void command("venue.suspend", venueText(selectedVenue.id), venueNumber(selectedVenue.revision), { reasonCode: "CLUB_SUSPEND" })} type="button">Suspender</button> : null}</div></div><form className={styles.formGrid} key={venueText(selectedVenue.id)} onSubmit={updateVenue}><label>Nombre<input name="name" defaultValue={venueText(selectedVenue.name)} required /></label><label>Slug<input name="slug" defaultValue={venueText(selectedVenue.slug)} required /></label><label>Municipio<input name="municipality" defaultValue={venueText(selectedVenue.municipality)} /></label><label>Zona general<input name="generalArea" defaultValue={venueText(selectedVenue.general_area)} /></label><label>Zona horaria<input name="timezone" defaultValue={venueText(selectedVenue.timezone)} /></label><label>Dirección privada<input name="privateAddress" defaultValue={venueText(selectedVenue.private_address)} /></label><label>Contacto<input name="privateContactName" defaultValue={venueText(selectedVenue.private_contact_name)} /></label><label>Teléfono<input name="privateContactPhone" defaultValue={venueText(selectedVenue.private_contact_phone)} /></label><label>Email<input name="privateContactEmail" type="email" defaultValue={venueText(selectedVenue.private_contact_email)} /></label><label className={styles.wide}>Acceso privado<textarea name="privateAccessInstructions" rows={2} defaultValue={venueText(selectedVenue.private_access_instructions)} /></label><label className={styles.wide}>Descripción<textarea name="description" rows={3} defaultValue={venueText(selectedVenue.description)} /></label><button className={styles.action} disabled={busy || desk?.canManageVenues !== true} type="submit">Guardar instalación</button></form></section>
      <section className={styles.surface}><span className={styles.eyebrow}>Pistas</span><h2>Crear pista</h2><form className={styles.formGrid} onSubmit={createPitch}><label>Nombre<input name="name" required /></label><label>Slug<input name="slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" /></label><label>Superficie<select name="surface" defaultValue="ARTIFICIAL_GRASS"><option value="ARTIFICIAL_GRASS">Césped artificial</option><option value="NATURAL_GRASS">Césped natural</option><option value="PARQUET">Parquet</option><option value="CONCRETE">Hormigón</option><option value="OTHER">Otra</option></select></label><label>Entorno<select name="environment" defaultValue="OUTDOOR"><option value="OUTDOOR">Exterior</option><option value="INDOOR">Interior</option><option value="COVERED">Cubierta</option></select></label><label>Modalidades<select name="modalities" multiple defaultValue={["F7"]}><option value="F5">F5</option><option value="F7">F7</option><option value="F11">F11</option><option value="FUTSAL">Fútbol sala</option></select></label><label>Visibilidad<select name="visibility" defaultValue="PRIVATE"><option value="PRIVATE">Privada</option><option value="UNLISTED">No listada</option><option value="PUBLIC">Pública</option></select></label><label>Duración mínima<input name="minimumSlotMinutes" type="number" min={30} max={240} defaultValue={60} /></label><label>Margen<input name="bufferMinutes" type="number" min={0} max={120} defaultValue={0} /></label><label className={styles.filterToggle}><input name="hasLighting" type="checkbox" />Iluminación</label><label className={styles.filterToggle}><input name="hasChangingRooms" type="checkbox" />Vestuarios</label><label className={styles.filterToggle}><input name="hasShowers" type="checkbox" />Duchas</label><label className={styles.filterToggle}><input name="isAccessible" type="checkbox" />Accesible</label><label className={styles.filterToggle}><input name="hasParking" type="checkbox" />Aparcamiento</label><label>Tarifa<select name="publicRateKind" defaultValue="CONTACT_CLUB"><option value="CONTACT_CLUB">Contactar Club</option><option value="FIXED_QUOTE">Importe orientativo</option></select></label><button className={styles.action} disabled={busy || desk?.canManageVenues !== true} type="submit">Crear pista</button></form><div className={styles.rows}>{venuePitches.map((pitch) => <article key={venueText(pitch.id)}><div><strong>{venueText(pitch.name)}</strong><small>{venueTextArray(pitch.modalities).join(" · ")} · {venueStatusLabel(pitch.status)}</small></div><div className={styles.actions}>{venueText(pitch.status) === "ACTIVE" ? <button className={styles.dangerAction} disabled={busy} onClick={() => void command("pitch.maintenance", venueText(pitch.id), venueNumber(pitch.revision), { reasonCode: "CLUB_MAINTENANCE" })} type="button">Mantenimiento</button> : null}{venueText(pitch.status) === "MAINTENANCE" ? <button className={styles.action} disabled={busy} onClick={() => void command("pitch.restore", venueText(pitch.id), venueNumber(pitch.revision), { reasonCode: "CLUB_RESTORE" })} type="button">Reabrir</button> : null}</div></article>)}</div></section>
      <section className={styles.twoColumns}><div className={styles.surface}><span className={styles.eyebrow}>Horario base</span><h2>Añadir disponibilidad</h2><form className={styles.formGrid} onSubmit={createTemplate}><label>Pista<select name="pitchId">{venuePitches.map((pitch) => <option key={venueText(pitch.id)} value={venueText(pitch.id)}>{venueText(pitch.name)}</option>)}</select></label><label>Día<select name="weekday" defaultValue="1"><option value="1">Lunes</option><option value="2">Martes</option><option value="3">Miércoles</option><option value="4">Jueves</option><option value="5">Viernes</option><option value="6">Sábado</option><option value="7">Domingo</option></select></label><label>Desde<input name="startLocalTime" type="time" required /></label><label>Hasta<input name="endLocalTime" type="time" required /></label><label>Duración<input name="slotMinutes" type="number" min={30} max={240} defaultValue={60} /></label><label>Margen<input name="bufferMinutes" type="number" min={0} max={120} defaultValue={0} /></label><label>Válido desde<input name="validFrom" type="date" required /></label><label>Válido hasta<input name="validUntil" type="date" /></label><label>Modalidad<select name="modality" defaultValue="F7"><option value="F5">F5</option><option value="F7">F7</option><option value="F11">F11</option><option value="FUTSAL">Fútbol sala</option></select></label><button className={styles.action} disabled={busy || !venuePitches.length} type="submit">Añadir horario</button></form><p className={styles.muted}>{templates.filter((item) => venuePitches.some((pitch) => venueText(pitch.id) === venueText(item.pitch_id))).length} reglas de disponibilidad.</p></div><div className={styles.surface}><span className={styles.eyebrow}>Excepciones</span><h2>Bloqueo o apertura especial</h2><form className={styles.formGrid} onSubmit={createException}><label>Pista<select name="pitchId">{venuePitches.map((pitch) => <option key={venueText(pitch.id)} value={venueText(pitch.id)}>{venueText(pitch.name)}</option>)}</select></label><label>Tipo<select name="kind" defaultValue="MAINTENANCE"><option value="MAINTENANCE">Mantenimiento</option><option value="CLOSED">Cierre</option><option value="BLOCKED">Bloqueo</option><option value="SPECIAL_OPENING">Apertura especial</option></select></label><label>Desde<input name="startsAt" type="datetime-local" required /></label><label>Hasta<input name="endsAt" type="datetime-local" required /></label><label>Motivo público<input name="publicReason" /></label><label>Motivo interno<input name="privateReason" /></label><label>Visibilidad<select name="visibility" defaultValue="PUBLIC"><option value="PUBLIC">Pública</option><option value="PRIVATE">Privada</option></select></label><label>Prioridad<input name="priority" type="number" defaultValue={100} /></label><button className={styles.action} disabled={busy || !venuePitches.length} type="submit">Crear excepción</button></form><p className={styles.muted}>{exceptions.filter((item) => venuePitches.some((pitch) => venueText(pitch.id) === venueText(item.pitch_id))).length} excepciones registradas.</p></div></section></> : <p className={styles.empty}>Crea o selecciona un Campo para comenzar.</p>}
    {venueText(selectedVenue.lifecycle) === "ACTIVE" ? <section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Perfil público</span><h2>Consentimiento de publicación</h2><p>Publica descripción, zona general y tarifas consentidas. La dirección y las coordenadas privadas permanecen ocultas.</p></div><button className={styles.action} disabled={busy || !venuePitches.length} onClick={() => void command("venue.publication.consent", venueText(selectedVenue.id), venueNumber(selectedVenue.revision), { addressMode: "AREA_ONLY", publicRateAllowed: true, reasonCode: "CLUB_PUBLICATION_CONSENT", selectedFields: { address: false, coordinates: false, description: true } })} type="button">Publicar Campo</button></div></section> : null}
  </div>;

  const reservationView = <div className={styles.content}>
    <section className={styles.metricGrid}><div className={styles.metric}><span className={styles.eyebrow}>Solicitudes</span><strong>{requests.length}</strong></div><div className={styles.metric}><span className={styles.eyebrow}>Holds activos</span><strong>{holds.filter((item) => venueText(item.status) === "ACTIVE").length}</strong></div><div className={styles.metric}><span className={styles.eyebrow}>Confirmadas</span><strong>{reservations.filter((item) => venueText(item.status) === "CONFIRMED").length}</strong></div><div className={styles.metric}><span className={styles.eyebrow}>Conflictos</span><strong>{conflicts.length}</strong></div></section>
    {conflicts.length ? <section className={styles.surface}><span className={styles.eyebrow}>Atención</span><h2>Conflictos de disponibilidad</h2><div className={styles.rows}>{conflicts.map((item) => <article key={venueText(item.exceptionId) + venueText(item.reservationId)}><div><strong>{venueStatusLabel(item.exceptionKind)}</strong><small>{venueDateTime(item.startsAt)} → {venueDateTime(item.endsAt)}</small></div><span>{venueStatusLabel(item.reservationStatus)}</span></article>)}</div></section> : null}
    <section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Bandeja</span><h2>Solicitudes</h2></div><span>{requests.length}</span></div><div className={styles.timeline}>{requests.map((request) => {
      const status = venueText(request.status);
      const proposal = venueRecord(request.current_proposal);
      const actionable = new Set(["SUBMITTED", "UNDER_REVIEW", "COUNTER_PROPOSED"]).has(status);
      return <article className={styles.timelineItem} key={venueText(request.id)}><div><span className={styles.eyebrow}>{venueStatusLabel(status)}</span><strong>{venueText(request.modality)} · {venueDateTime(request.starts_at, venueText(request.timezone))}</strong><small>{venueText(request.purpose).replaceAll("_", " ")}</small>{venueText(request.message) ? <p>{venueText(request.message)}</p> : null}</div><div className={styles.actions}>{status === "SUBMITTED" ? <button className={styles.secondaryAction} disabled={busy} type="button" onClick={() => void command("reservation.review.start", venueText(request.id), venueNumber(request.revision), { reasonCode: "CLUB_REVIEW" })}>Revisar</button> : null}{actionable ? <><button className={styles.secondaryAction} disabled={busy} type="button" onClick={() => void command("reservation.hold", venueText(request.id), venueNumber(request.revision), { expiresInMinutes: 15, reasonCode: "CLUB_HOLD" })}>Bloquear 15 min</button><button className={styles.dangerAction} disabled={busy} type="button" onClick={() => void command("reservation.reject", venueText(request.id), venueNumber(request.revision), { message: "No disponible", reasonCode: "CLUB_REJECT" })}>Rechazar</button></> : null}</div>{actionable ? <details className={styles.wide}><summary>Contrapropuesta o aceptación</summary><form className={styles.requestForm} onSubmit={(event) => reviewRequest(event, request, "reservation.counter")}><label>Pista<select name="pitchId" defaultValue={venueText(proposal.pitchId) || venueText(request.pitch_id)}>{pitches.filter((pitch) => venueText(pitch.venue_id) === venueText(request.venue_id)).map((pitch) => <option key={venueText(pitch.id)} value={venueText(pitch.id)}>{venueText(pitch.name)}</option>)}</select></label><label>Inicio<input name="localStart" type="datetime-local" defaultValue={localInput(proposal.localStart || request.requested_local_start)} required /></label><label>Fin<input name="localEnd" type="datetime-local" defaultValue={localInput(proposal.localEnd || request.requested_local_end)} required /></label><label>Importe €<input name="amount" type="number" min={0} step="0.01" /></label><label>Cancelación<input name="cancellationTerms" /></label><label>Mensaje<input name="message" /></label><label className={styles.wide}>Nota interna<textarea name="privateNotes" rows={2} /></label><div className={styles.actions}><button className={styles.secondaryAction} disabled={busy} type="submit">Enviar contrapropuesta</button><button className={styles.action} disabled={busy} type="button" onClick={(event) => { const form = event.currentTarget.closest("form"); if (form) void reviewRequest({ preventDefault() {}, currentTarget: form } as FormEvent<HTMLFormElement>, request, "reservation.accept"); }}>Aceptar solicitud</button></div></form></details> : null}</article>;
    })}</div>{!requests.length ? <p className={styles.empty}>No hay solicitudes para este Club.</p> : null}</section>
    <section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Operación</span><h2>Reservas y partidos</h2></div><span>{reservations.length}</span></div><div className={styles.rows}>{reservations.map((reservation) => { const binding = bindings.find((item) => venueText(item.reservation_id) === venueText(reservation.id)); return <article key={venueText(reservation.id)}><div><strong>{venueStatusLabel(reservation.status)}</strong><small>{venueDateTime(reservation.starts_at, venueText(reservation.timezone))}{binding ? " · partido vinculado" : ""}</small></div><div className={styles.actions}><Link className={styles.secondaryAction} href={"/reservas/" + venueText(reservation.id)}>Detalle</Link>{new Set(["PENDING_CONFIRMATION", "CONFIRMED"]).has(venueText(reservation.status)) ? <button className={styles.dangerAction} disabled={busy} type="button" onClick={() => void command("reservation.cancel", venueText(reservation.id), venueNumber(reservation.revision), { reasonCode: "CLUB_CANCEL" })}>Cancelar</button> : null}</div></article>; })}</div></section>
  </div>;

  return <OfficialProductShellV2 active="competir" perspective="club-organizer" context={context}><main className={styles.page} data-mobile-tab="competir">
    <header className={styles.hero}><div><span className={styles.eyebrow}>Club</span><h1>{mode === "venues" ? "Campos y disponibilidad" : "Mesa de reservas"}</h1><p>{mode === "venues" ? "Inventario, pistas, horarios y excepciones." : "Solicitudes, holds, conflictos y reservas canónicas."}</p></div><div className={styles.actions}><Link className={mode === "venues" ? styles.action : styles.secondaryAction} href={"/clubes/gestionar/campos?club=" + selectedClubId}>Campos</Link><Link className={mode === "reservations" ? styles.action : styles.secondaryAction} href={"/clubes/gestionar/reservas?club=" + selectedClubId}>Reservas</Link><Link className={styles.secondaryAction} href="/clubes/gestionar">Club</Link></div></header>
    {message ? <p className={styles.message} data-tone={/confirmado|actualizada/i.test(message) ? "success" : /no |sin conexión|rechazó|inicia/i.test(message) ? "danger" : "info"}>{message}</p> : null}
    <div className={styles.workspace}><aside className={styles.sidebar}><span className={styles.eyebrow}>Mis Clubs</span>{clubs.map((item) => { const club = venueRecord(item.club); return <button aria-current={venueText(club.id) === selectedClubId ? "page" : undefined} key={venueText(club.id)} type="button" onClick={() => void changeClub(venueText(club.id))}>{venueText(club.name)}</button>; })}{mode === "venues" && venues.length ? <><span className={styles.eyebrow}>Instalaciones</span>{venues.map((venue) => <button aria-current={venueText(venue.id) === venueText(selectedVenue.id) ? "page" : undefined} key={venueText(venue.id)} type="button" onClick={() => setSelectedVenueId(venueText(venue.id))}>{venueText(venue.name)}</button>)}</> : null}</aside><section className={styles.content}>{loading && !desk ? <p className={styles.empty}>Cargando estado canónico...</p> : mode === "venues" ? venueView : reservationView}</section></div>
  </main></OfficialProductShellV2>;
}
