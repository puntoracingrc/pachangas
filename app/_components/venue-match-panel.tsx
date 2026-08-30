"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "../supabaseClient";
import {
  readVenueCache,
  venueDateTime,
  venueRecord,
  venueStatusLabel,
  venueText,
  venueUuid,
  writeVenueCache,
  type VenueJson,
} from "../venue-operations-contract";
import styles from "./venue-match-panel.module.css";

function cacheProjection(data: VenueJson) {
  const location = venueRecord(data.operationalLocation);
  return {
    actionRequired: data.actionRequired,
    binding: data.binding,
    bindingStatus: data.bindingStatus,
    canonicalMatchId: data.canonicalMatchId,
    operationalLocation: venueText(location.address) ? {
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
    } : null,
    pitch: data.pitch,
    refereeScheduleState: data.refereeScheduleState,
    reservation: data.reservation,
    venue: data.venue,
  };
}

export function VenueMatchPanel({
  canManage,
  canonicalMatchId,
  legacyPlace,
}: {
  canManage: boolean;
  canonicalMatchId?: string;
  legacyPlace?: string;
}) {
  const safeMatchId = venueUuid(canonicalMatchId);
  const [data, setData] = useState<VenueJson | null>(() => safeMatchId ? readVenueCache("match-" + safeMatchId) : null);
  const [cached, setCached] = useState(Boolean(data));
  const [message, setMessage] = useState("");

  const load = useCallback(async (token: string, realtime = false) => {
    if (!safeMatchId) return;
    try {
      const response = await fetch("/api/venues/match/" + safeMatchId, { cache: "no-store", headers: { Authorization: "Bearer " + token } });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || "No se pudo recuperar Campo y reserva.");
      setData(body);
      setCached(false);
      writeVenueCache("match-" + safeMatchId, cacheProjection(body));
      if (realtime) setMessage("Campo y reserva actualizados.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar Campo y reserva.");
    }
  }, [safeMatchId]);

  useEffect(() => {
    const client = supabase;
    if (!client || !safeMatchId) return;
    let active = true;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(({ data: sessionData }) => {
      if (!active) return;
      const token = sessionData.session?.access_token ?? "";
      if (!token) {
        setMessage("Inicia sesión para consultar la reserva canónica del partido.");
        return;
      }
      void load(token);
      channel = client.channel("venue-match:" + safeMatchId)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_venue_invalidations" }, () => { if (active) void load(token, true); })
        .subscribe((status) => { if (status === "SUBSCRIBED" && active) void load(token); });
    });
    return () => { active = false; if (channel) void client.removeChannel(channel); };
  }, [load, safeMatchId]);

  const venue = venueRecord(data?.venue);
  const pitch = venueRecord(data?.pitch);
  const reservation = venueRecord(data?.reservation);
  const binding = venueRecord(data?.binding);
  const location = venueRecord(data?.operationalLocation);
  const status = venueText(binding.status) || venueText(data?.bindingStatus) || "UNASSIGNED";

  return <section className={styles.panel} aria-label="Campo y reserva">
    <header className={styles.heading}><div><span>Partido</span><h2>Campo y reserva</h2></div><strong>{venueStatusLabel(status)}</strong></header>
    {!safeMatchId ? <><p className={styles.message}>Este partido de grupo todavía usa el campo de compatibilidad: {legacyPlace || "por confirmar"}.</p><div className={styles.actions}><Link href="/campos">Buscar Campo</Link>{canManage ? <Link href="/clubes/gestionar/reservas">Gestionar reservas</Link> : <Link href="/reservas">Mis reservas</Link>}</div></> : <>
      {cached ? <p className={styles.message}>Copia local autorizada · verificando con el servidor.</p> : null}
      {message ? <p className={styles.message}>{message}</p> : null}
      {status === "UNASSIGNED" ? <div className={styles.card}><small>Sin sede</small><h3>Campo por confirmar</h3><p>El partido mantiene su identidad canónica, pero todavía no tiene una reserva vinculada.</p></div> : <div className={styles.grid}>
        <article className={styles.card}><small>Instalación</small><h3>{venueText(venue.name) || "Campo"}</h3><p>{venueText(pitch.name) || "Pista"} · {venueStatusLabel(reservation.status)}</p><p>{venueDateTime(reservation.starts_at, venueText(reservation.timezone) || "Europe/Madrid")}</p></article>
        <article className={styles.card}><small>Acceso autorizado</small><h3>{venueText(location.address) || "Ubicación protegida"}</h3><p>{venueText(location.address) ? "Visible para participantes, organización y árbitro autorizados." : "Se mostrará cuando tu rol y el estado de la reserva lo permitan."}</p></article>
        <article className={styles.card}><small>Árbitro</small><h3>{venueStatusLabel(data?.refereeScheduleState || "UNASSIGNED")}</h3><p>{venueText(data?.actionRequired) ? "El cambio de campo requiere una acción operativa." : "Sin acción pendiente por cambio de sede."}</p></article>
      </div>}
      {venueText(data?.actionRequired) ? <p className={styles.message + " " + styles.warning}>Acción requerida: {venueStatusLabel(data?.actionRequired)}. El partido no se cancela automáticamente.</p> : null}
      <div className={styles.actions}>{venueText(reservation.id) ? <Link href={"/reservas/" + venueText(reservation.id)}>Abrir reserva</Link> : <Link href="/campos">Buscar Campo</Link>}{canManage ? <Link href={"/clubes/gestionar/reservas?match=" + safeMatchId}>Cambiar o vincular</Link> : <Link href="/reservas">Mis reservas</Link>}</div>
    </>}
  </section>;
}
