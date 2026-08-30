"use client";

import Link from "next/link";
import { useMemo, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { clientWriteFetch } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import {
  venueArray,
  venueDateTime,
  venueMoney,
  venueNumber,
  venueRecord,
  venueText,
  venueTextArray,
  type VenueJson,
} from "../../venue-operations-contract";
import styles from "../../venue-operations.module.css";

function tomorrow() {
  const date = new Date(Date.now() + 86_400_000);
  return date.toISOString().slice(0, 10);
}

function serviceLabels(pitch: VenueJson) {
  return [
    pitch.hasLighting ? "Iluminación" : "",
    pitch.hasChangingRooms ? "Vestuarios" : "",
    pitch.hasShowers ? "Duchas" : "",
    pitch.isAccessible ? "Accesible" : "",
    pitch.hasParking ? "Aparcamiento" : "",
  ].filter(Boolean);
}

function localValue(value: unknown) {
  return venueText(value).replace(" ", "T").slice(0, 19);
}

export function PublicVenueProfile({ venue }: { venue: VenueJson }) {
  const pitches = useMemo(() => venueArray(venue.pitches), [venue.pitches]);
  const [pitchId, setPitchId] = useState(() => venueText(pitches[0]?.pitchId));
  const selectedPitch = pitches.find((pitch) => venueText(pitch.pitchId) === pitchId) ?? pitches[0] ?? {};
  const modalities = venueTextArray(selectedPitch.modalities);
  const [modality, setModality] = useState(() => modalities[0] ?? "F7");
  const [date, setDate] = useState(tomorrow);
  const [availability, setAvailability] = useState<VenueJson | null>(null);
  const [selectedSlot, setSelectedSlot] = useState<VenueJson | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [confirmedRequestId, setConfirmedRequestId] = useState("");
  const club = venueRecord(venue.club);
  const coordinates = venueRecord(venue.coordinates);

  async function loadAvailability() {
    if (!pitchId || !date || !modality) return;
    const start = new Date(date + "T00:00:00");
    const end = new Date(start.valueOf() + 7 * 86_400_000);
    setLoading(true);
    setMessage("");
    try {
      const params = new URLSearchParams({
        endsAt: end.toISOString(),
        modality,
        pitchId,
        startsAt: start.toISOString(),
      });
      const response = await fetch("/api/venues/availability?" + params.toString(), { cache: "no-store" });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.error) || "No se pudo consultar la disponibilidad.");
      setAvailability(body);
      setSelectedSlot(null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo consultar la disponibilidad.");
    } finally {
      setLoading(false);
    }
  }

  async function command(token: string, action: string, aggregateId: string, expectedRevision: number, payload: VenueJson) {
    const response = await clientWriteFetch("api:venue-operations-command", "/api/venues/command", {
      body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: crypto.randomUUID(), payload }),
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      method: "POST",
    });
    const body = await response.json() as VenueJson;
    if (!response.ok) throw new Error(venueText(body.message) || venueText(body.error) || "La operación no fue confirmada.");
    return venueRecord(body.canonical);
  }

  async function requestReservation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedSlot) {
      setMessage("Selecciona primero una franja disponible.");
      return;
    }
    if (!navigator.onLine) {
      setMessage("Sin conexión: puedes consultar la copia cargada, pero las solicitudes solo se envían al servidor.");
      return;
    }
    const session = await supabase?.auth.getSession();
    const token = session?.data.session?.access_token ?? "";
    if (!token) {
      setMessage("Inicia sesión para enviar una solicitud de reserva.");
      return;
    }
    const form = new FormData(event.currentTarget);
    setLoading(true);
    setMessage("Enviando intención al servidor...");
    try {
      const created = await command(token, "reservation.request.create", "", 0, {
        alternatives: [],
        criteria: { source: "public_venue_profile" },
        localEnd: localValue(selectedSlot.localEnd),
        localStart: localValue(selectedSlot.localStart),
        message: String(form.get("message") ?? "").trim(),
        modality,
        offsetMinutes: venueNumber(selectedSlot.offsetMinutes),
        pitchId,
        purpose: "MATCH",
        reasonCode: "PUBLIC_REQUEST",
        requesterKind: "USER",
        timezone: venueText(selectedSlot.timezone) || venueText(availability?.timezone) || "Europe/Madrid",
        venueId: venueText(venue.venueId),
      });
      const requestId = venueText(created.aggregateId);
      const revision = venueNumber(created.confirmedRevision);
      if (!requestId || !revision) throw new Error("El servidor no devolvió la solicitud canónica.");
      const submitted = await command(token, "reservation.request.submit", requestId, revision, { reasonCode: "PUBLIC_REQUEST_SUBMIT" });
      setConfirmedRequestId(requestId);
      setMessage("Solicitud enviada y confirmada por PostgreSQL. Revisión " + venueNumber(submitted.confirmedRevision) + ".");
    } catch (error) {
      setSelectedSlot(null);
      setMessage(error instanceof Error ? error.message : "La solicitud no fue confirmada.");
    } finally {
      setLoading(false);
    }
  }

  return <OfficialProductShellV2
    active="mercado"
    perspective="free-agent"
    context={{ detail: venueText(venue.municipality) || "Perfil público", eyebrow: "Campos", status: "Público", title: venueText(venue.name) || "Campo" }}
  >
    <main className={styles.page} data-mobile-tab="mercado">
      <header className={styles.hero}>
        <div><span className={styles.eyebrow}>{venueText(club.name) || "Club"}</span><h1>{venueText(venue.name) || "Campo"}</h1><p>{[venueText(venue.municipality), venueText(venue.generalArea)].filter(Boolean).join(" · ")}</p></div>
        <div className={styles.actions}><Link className={styles.secondaryAction} href="/campos">Volver a Campos</Link><Link className={styles.secondaryAction} href="/reservas">Mis reservas</Link></div>
      </header>
      <section className={styles.twoColumns}>
        <div className={styles.content}>
          <section className={styles.surface}><span className={styles.eyebrow}>Instalación</span><h2>Información pública</h2><p>{venueText(venue.description) || "El Club todavía no ha añadido una descripción pública."}</p>{venueText(venue.address) ? <p><strong>Dirección pública:</strong> {venueText(venue.address)}</p> : <p className={styles.muted}>La dirección exacta se entrega a las personas autorizadas tras confirmar la reserva.</p>}{venueText(coordinates.precision) ? <p className={styles.muted}>Coordenadas {venueText(coordinates.precision).toLocaleLowerCase("es-ES")} publicadas con consentimiento.</p> : null}</section>
          <section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Pistas</span><h2>Modalidades y servicios</h2></div><span>{pitches.length}</span></div><div className={styles.pitchGrid}>{pitches.map((pitch) => <article className={styles.pitchCard} key={venueText(pitch.pitchId)}><div><h3>{venueText(pitch.name) || "Pista"}</h3><p>{venueText(pitch.environment).replaceAll("_", " ")} · {venueText(pitch.surface).replaceAll("_", " ")}</p></div><div className={styles.chips}>{venueTextArray(pitch.modalities).map((item) => <span className={styles.chip} key={item}>{item === "FUTSAL" ? "Fútbol sala" : item}</span>)}</div><div className={styles.services}>{serviceLabels(pitch).map((item) => <span className={styles.chip} key={item}>{item}</span>)}</div>{venueRecord(pitch.publicRate).amountMinor !== undefined ? <p><strong>{venueMoney(venueRecord(pitch.publicRate).amountMinor, venueRecord(pitch.publicRate).currency)}</strong> · Pago fuera de Pachangas IQ.</p> : null}</article>)}</div></section>
        </div>
        <aside className={styles.panel}>
          <span className={styles.eyebrow}>Disponibilidad</span><h2>Solicitar una franja</h2>
          <div className={styles.formGrid}>
            <label>Pista<select value={pitchId} onChange={(event) => { const next = event.target.value; setPitchId(next); const pitch = pitches.find((item) => venueText(item.pitchId) === next); setModality(venueTextArray(pitch?.modalities)[0] ?? "F7"); setAvailability(null); setSelectedSlot(null); }}>{pitches.map((pitch) => <option key={venueText(pitch.pitchId)} value={venueText(pitch.pitchId)}>{venueText(pitch.name)}</option>)}</select></label>
            <label>Modalidad<select value={modality} onChange={(event) => { setModality(event.target.value); setAvailability(null); setSelectedSlot(null); }}>{venueTextArray(selectedPitch.modalities).map((item) => <option key={item} value={item}>{item === "FUTSAL" ? "Fútbol sala" : item}</option>)}</select></label>
            <label>Desde<input type="date" value={date} onChange={(event) => { setDate(event.target.value); setAvailability(null); setSelectedSlot(null); }} /></label>
            <button className={styles.secondaryAction} type="button" disabled={loading || !pitchId} onClick={() => void loadAvailability()}>{loading ? "Consultando..." : "Ver 7 días"}</button>
          </div>
          {availability ? <div className={styles.slotGrid}>{venueArray(availability.items).map((slot) => {
            const available = venueText(slot.status) === "AVAILABLE";
            const active = venueText(selectedSlot?.startsAt) === venueText(slot.startsAt);
            return <button className={styles.slotButton} aria-pressed={active} disabled={!available} key={venueText(slot.startsAt)} type="button" onClick={() => setSelectedSlot(slot)}>{venueDateTime(slot.startsAt, venueText(slot.timezone) || "Europe/Madrid")} · {available ? "Libre" : venueText(slot.status)}</button>;
          })}</div> : null}
          {availability && !venueArray(availability.items).length ? <p className={styles.empty}>No hay franjas publicadas durante estos siete días.</p> : null}
          <form className={styles.requestForm} onSubmit={requestReservation}>
            <label className={styles.wide}>Mensaje opcional<textarea name="message" maxLength={2000} rows={3} placeholder="Contexto del partido o necesidades de la reserva" /></label>
            <button className={styles.action + " " + styles.wide} disabled={loading || !selectedSlot || Boolean(confirmedRequestId)} type="submit">{confirmedRequestId ? "Solicitud enviada" : "Solicitar reserva"}</button>
          </form>
          {message ? <p className={styles.message} data-tone={confirmedRequestId ? "success" : /no |sin conexión|error|inicia/i.test(message) ? "danger" : "info"}>{message}</p> : null}
          <p className={styles.muted}>Pachangas IQ gestiona la solicitud y el estado. Cualquier pago se acuerda directamente con el Club.</p>
        </aside>
      </section>
    </main>
  </OfficialProductShellV2>;
}
