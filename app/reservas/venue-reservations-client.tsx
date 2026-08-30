"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  readVenueCache,
  venueArray,
  venueDateTime,
  venueNumber,
  venueRecord,
  venueStatusLabel,
  venueText,
  writeVenueCache,
  type VenueJson,
} from "../venue-operations-contract";
import styles from "../venue-operations.module.css";

function cacheProjection(data: VenueJson) {
  return {
    items: venueArray(data.items).map((item) => {
      const location = venueRecord(item.operationalLocation);
      return {
        request: item.request,
        reservation: item.reservation,
        hold: item.hold,
        venue: item.venue,
        operationalLocation: venueText(location.address) ? {
          address: venueText(location.address),
          latitude: location.latitude,
          longitude: location.longitude,
        } : null,
      };
    }),
    serverSequence: venueNumber(data.serverSequence),
  };
}

function nextAction(request: VenueJson, reservation: VenueJson, hold: VenueJson) {
  const reservationStatus = venueText(reservation.status);
  const requestStatus = venueText(request.status);
  if (reservationStatus === "PENDING_CONFIRMATION") return "Confirma o cancela la reserva";
  if (reservationStatus === "CONFIRMED") return "Consulta el acceso y el partido vinculado";
  if (requestStatus === "COUNTER_PROPOSED") return "Revisa la contrapropuesta";
  if (requestStatus === "HELD" && venueText(hold.expiresAt)) return "Bloqueo hasta " + venueDateTime(hold.expiresAt);
  if (requestStatus === "SUBMITTED" || requestStatus === "UNDER_REVIEW") return "Esperando respuesta del Club";
  if (requestStatus === "DRAFT") return "Envía la solicitud";
  return "Sin acción pendiente";
}

export function VenueReservationsClient() {
  const [data, setData] = useState<VenueJson | null>(null);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [cached, setCached] = useState(false);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState(supabase ? "" : "Supabase no está configurado.");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (actorId: string, token: string, reason: "initial" | "manual" | "mutation" | "realtime") => {
    try {
      const response = await fetch("/api/venues/my", { cache: "no-store", headers: { Authorization: "Bearer " + token } });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || "No se pudieron recuperar tus reservas.");
      setData(body);
      setCached(false);
      writeVenueCache("my", cacheProjection(body), actorId);
      if (reason === "realtime") setMessage("Reservas actualizadas desde el servidor.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudieron recuperar tus reservas.");
    } finally {
      setLoading(false);
    }
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
      if (!actorId || !token) {
        setLoading(false);
        setMessage("Inicia sesión para consultar tus reservas.");
        return;
      }
      setUserId(actorId);
      setAccessToken(token);
      const local = readVenueCache("my", actorId);
      if (local) {
        setData(local);
        setCached(true);
        setLoading(false);
      }
      void loadCanonical(actorId, token, "initial");
      const reconcile = (delay = 120) => {
        if (realtimeTimer.current) clearTimeout(realtimeTimer.current);
        realtimeTimer.current = window.setTimeout(() => {
          if (active) void loadCanonical(actorId, token, "realtime");
        }, delay);
      };
      channel = client.channel("venue-reservations:" + actorId)
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
  }, [loadCanonical]);

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: VenueJson) {
    if (!accessToken || !userId || !navigator.onLine) {
      setMessage("Sin conexión: las lecturas cargadas siguen disponibles, pero no se ha enviado ningún cambio.");
      return;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setLoading(true);
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
      await loadCanonical(userId, accessToken, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "La operación no fue confirmada.";
      setMessage(/STALE_REVISION/i.test(detail) ? "La revisión cambió. Se ha recargado el estado canónico." : detail);
      if (/STALE_REVISION/i.test(detail)) await loadCanonical(userId, accessToken, "manual");
    } finally {
      setLoading(false);
    }
  }

  function counter(event: FormEvent<HTMLFormElement>, request: VenueJson) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const localStart = String(form.get("localStart") ?? "");
    const localEnd = String(form.get("localEnd") ?? "");
    void command("reservation.counter", venueText(request.id), venueNumber(request.revision), {
      localEnd,
      localStart,
      message: String(form.get("message") ?? "").trim(),
      offsetMinutes: venueNumber(request.resolved_offset_minutes),
      pitchId: venueText(request.pitch_id),
      reasonCode: "REQUESTER_COUNTER",
      terms: venueRecord(venueRecord(request.currentProposal).terms),
      timezone: venueText(request.timezone),
    });
  }

  const items = useMemo(() => venueArray(data?.items), [data]);
  const active = items.filter((item) => !new Set(["CANCELLED", "REJECTED", "WITHDRAWN", "EXPIRED", "CONSUMED"]).has(venueText(venueRecord(item.reservation).status) || venueText(venueRecord(item.request).status)));
  const history = items.filter((item) => !active.includes(item));

  const renderItem = (item: VenueJson) => {
    const request = venueRecord(item.request);
    const reservation = venueRecord(item.reservation);
    const hold = venueRecord(item.hold);
    const venue = venueRecord(item.venue);
    const proposal = venueRecord(request.currentProposal);
    const status = venueText(reservation.status) || venueText(request.status);
    const reservationId = venueText(reservation.id);
    return <article className={styles.timelineItem} key={venueText(request.id)}>
      <div><span className={styles.eyebrow}>{venueStatusLabel(status)}</span><strong>{venueText(venue.name) || "Campo"}</strong><small>{venueDateTime(reservation.starts_at || request.starts_at, venueText(request.timezone) || "Europe/Madrid")} · {venueText(request.modality)}</small><p>{nextAction(request, reservation, hold)}</p>{venueText(proposal.localStart) ? <small>Propuesta: {venueText(proposal.localStart).replace("T", " ")} → {venueText(proposal.localEnd).replace("T", " ")}</small> : null}</div>
      <div className={styles.actions}>
        {reservationId ? <Link className={styles.secondaryAction} href={"/reservas/" + reservationId}>Abrir</Link> : null}
        {status === "DRAFT" ? <button className={styles.action} disabled={loading} type="button" onClick={() => void command("reservation.request.submit", venueText(request.id), venueNumber(request.revision), { reasonCode: "USER_SUBMIT" })}>Enviar</button> : null}
        {status === "PENDING_CONFIRMATION" ? <button className={styles.action} disabled={loading} type="button" onClick={() => void command("reservation.confirm", reservationId, venueNumber(reservation.revision), { reasonCode: "USER_CONFIRM" })}>Confirmar</button> : null}
        {status === "COUNTER_PROPOSED" && venueText(proposal.proposedByKind) === "CLUB" ? <button className={styles.action} disabled={loading} type="button" onClick={() => void command("reservation.accept", venueText(request.id), venueNumber(request.revision), { reasonCode: "USER_ACCEPT_COUNTER" })}>Aceptar propuesta</button> : null}
        {new Set(["DRAFT", "SUBMITTED", "COUNTER_PROPOSED"]).has(status) ? <button className={styles.dangerAction} disabled={loading} type="button" onClick={() => void command("reservation.request.withdraw", venueText(request.id), venueNumber(request.revision), { reasonCode: "USER_WITHDRAW" })}>Retirar</button> : null}
      </div>
      {status === "COUNTER_PROPOSED" ? <details className={styles.wide}><summary>Proponer otra franja</summary><form className={styles.requestForm} onSubmit={(event) => counter(event, request)}><label>Inicio local<input name="localStart" type="datetime-local" defaultValue={venueText(proposal.localStart).slice(0, 16)} required /></label><label>Fin local<input name="localEnd" type="datetime-local" defaultValue={venueText(proposal.localEnd).slice(0, 16)} required /></label><label className={styles.wide}>Mensaje<textarea name="message" rows={2} /></label><button className={styles.secondaryAction} disabled={loading} type="submit">Enviar alternativa</button></form></details> : null}
    </article>;
  };

  return <OfficialProductShellV2
    active="competir"
    perspective="team-owner"
    context={{ detail: cached ? "Copia local · verificando" : "Servidor canónico", eyebrow: "Equipo · Campos", status: cached ? "Actualizando" : "En directo", title: "Reservas" }}
  >
    <main className={styles.page} data-mobile-tab="competir">
      <header className={styles.hero}><div><span className={styles.eyebrow}>Campos</span><h1>Mis reservas</h1><p>Solicitudes, contrapropuestas, bloqueos y reservas confirmadas.</p></div><div className={styles.actions}><Link className={styles.action} href="/campos">Buscar campo</Link><button className={styles.secondaryAction} disabled={!userId || loading} type="button" onClick={() => void loadCanonical(userId, accessToken, "manual")}>Actualizar</button></div></header>
      {message ? <p className={styles.message} data-tone={/confirmado|actualizadas/i.test(message) ? "success" : /no |sin conexión|rechazó|inicia/i.test(message) ? "danger" : "info"}>{message}</p> : null}
      {cached ? <p className={styles.cacheNote}>Mostrando una copia derivada. No contiene contactos ni instrucciones privadas.</p> : null}
      <section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>En curso</span><h2>Próxima acción</h2></div><span>{active.length}</span></div><div className={styles.timeline}>{active.map(renderItem)}</div>{!loading && !active.length ? <p className={styles.empty}>No tienes solicitudes activas.</p> : null}</section>
      <section className={styles.surface}><div className={styles.sectionHeading}><div><span className={styles.eyebrow}>Historial</span><h2>Operaciones cerradas</h2></div><span>{history.length}</span></div><div className={styles.timeline}>{history.map(renderItem)}</div>{!loading && !history.length ? <p className={styles.empty}>Todavía no hay historial de reservas.</p> : null}</section>
    </main>
  </OfficialProductShellV2>;
}
