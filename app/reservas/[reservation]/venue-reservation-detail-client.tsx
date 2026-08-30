"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { clientWriteFetch } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import {
  venueDateTime,
  venueMoney,
  venueNumber,
  venueRecord,
  venueStatusLabel,
  venueText,
  venueUuid,
  type VenueJson,
} from "../../venue-operations-contract";
import styles from "../../venue-operations.module.css";

export function VenueReservationDetailClient({ reservationId }: { reservationId: string }) {
  const safeId = venueUuid(reservationId);
  const [data, setData] = useState<VenueJson | null>(null);
  const [accessToken, setAccessToken] = useState("");
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState(safeId ? "" : "Reserva no válida.");
  const pending = useRef<{ id: string; key: string } | null>(null);

  const load = useCallback(async (token: string) => {
    if (!safeId) return;
    try {
      const response = await fetch("/api/venues/reservation/" + safeId, { cache: "no-store", headers: { Authorization: "Bearer " + token } });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || "No se pudo recuperar la reserva.");
      setData(body);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar la reserva.");
    } finally {
      setLoading(false);
    }
  }, [safeId]);

  useEffect(() => {
    const client = supabase;
    if (!client || !safeId) return;
    let active = true;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(({ data: sessionData }) => {
      if (!active) return;
      const token = sessionData.session?.access_token ?? "";
      if (!token) {
        setLoading(false);
        setMessage("Inicia sesión para consultar esta reserva.");
        return;
      }
      setAccessToken(token);
      void load(token);
      channel = client.channel("venue-reservation-detail:" + safeId)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_venue_invalidations" }, () => { if (active) void load(token); })
        .subscribe((status) => { if (status === "SUBSCRIBED" && active) void load(token); });
    });
    return () => { active = false; if (channel) void client.removeChannel(channel); };
  }, [load, safeId]);

  async function command(action: string, revision: number) {
    if (!accessToken || !navigator.onLine) {
      setMessage("Sin conexión: no se ha enviado ningún cambio.");
      return;
    }
    const payload = { reasonCode: action === "reservation.confirm" ? "USER_CONFIRM" : "USER_CANCEL" };
    const key = JSON.stringify({ action, reservationId: safeId, revision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setLoading(true);
    try {
      const response = await clientWriteFetch("api:venue-operations-command", "/api/venues/command", {
        body: JSON.stringify({ action, aggregateId: safeId, expectedRevision: revision, operationId: pending.current.id, payload }),
        headers: { Authorization: "Bearer " + accessToken, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as VenueJson;
      if (!response.ok) throw new Error(venueText(body.message) || "El cambio no fue confirmado.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await load(accessToken);
    } catch (error) {
      const detail = error instanceof Error ? error.message : "El cambio no fue confirmado.";
      setMessage(/STALE_REVISION/i.test(detail) ? "La revisión cambió. Se ha recargado el estado canónico." : detail);
      if (/STALE_REVISION/i.test(detail)) await load(accessToken);
    } finally {
      setLoading(false);
    }
  }

  const request = venueRecord(data?.request);
  const reservation = venueRecord(data?.reservation);
  const terms = venueRecord(data?.terms);
  const binding = venueRecord(data?.binding);
  const venue = venueRecord(data?.venue);
  const location = venueRecord(data?.operationalLocation);
  const status = venueText(reservation.status);

  return <OfficialProductShellV2 active="competir" perspective="team-owner" context={{ detail: status ? venueStatusLabel(status) : "Servidor canónico", eyebrow: "Campos", status: status || "Cargando", title: "Reserva" }}>
    <main className={styles.page} data-mobile-tab="competir">
      <header className={styles.hero}><div><span className={styles.eyebrow}>Reserva</span><h1>{venueText(venue.name) || "Detalle canónico"}</h1><p>{venueDateTime(reservation.starts_at || request.starts_at, venueText(request.timezone) || "Europe/Madrid")}</p></div><div className={styles.actions}><Link className={styles.secondaryAction} href="/reservas">Volver</Link>{status === "PENDING_CONFIRMATION" ? <button className={styles.action} disabled={loading} type="button" onClick={() => void command("reservation.confirm", venueNumber(reservation.revision))}>Confirmar</button> : null}{new Set(["PENDING_CONFIRMATION", "CONFIRMED"]).has(status) ? <button className={styles.dangerAction} disabled={loading} type="button" onClick={() => void command("reservation.cancel", venueNumber(reservation.revision))}>Cancelar</button> : null}</div></header>
      {message ? <p className={styles.message} data-tone={/confirmado/i.test(message) ? "success" : /no |sin conexión|inicia/i.test(message) ? "danger" : "info"}>{message}</p> : null}
      <section className={styles.twoColumns}>
        <div className={styles.content}>
          <section className={styles.surface}><span className={styles.eyebrow}>Estado</span><h2>{venueStatusLabel(status)}</h2><p>{venueText(request.modality)} · {venueDateTime(reservation.starts_at || request.starts_at, venueText(request.timezone) || "Europe/Madrid")} — {venueDateTime(reservation.ends_at || request.ends_at, venueText(request.timezone) || "Europe/Madrid")}</p>{venueText(binding.canonical_match_id) ? <Link href={"/?mobile=partido&canonicalMatch=" + venueText(binding.canonical_match_id)}>Ver partido vinculado</Link> : <p className={styles.muted}>Todavía no está vinculada a un partido canónico.</p>}</section>
          <section className={styles.surface}><span className={styles.eyebrow}>Ubicación autorizada</span><h2>Acceso</h2>{venueText(location.address) ? <><p><strong>{venueText(location.address)}</strong></p>{venueText(location.accessInstructions) ? <p>{venueText(location.accessInstructions)}</p> : null}</> : <p className={styles.empty}>La ubicación privada todavía no está disponible para tu rol o estado de reserva.</p>}</section>
        </div>
        <aside className={styles.panel}><span className={styles.eyebrow}>Condiciones</span><h2>{venueText(terms.kind) || "Sin importe publicado"}</h2>{terms.amountMinor !== undefined ? <p><strong>{venueMoney(terms.amountMinor, terms.currency)}</strong></p> : null}{venueText(terms.cancellationTerms) ? <p>{venueText(terms.cancellationTerms)}</p> : null}<p className={styles.message}>{venueText(data?.paymentNotice) || "Pachangas IQ no procesa el pago de esta reserva."}</p>{venueText(location.contactName) ? <div className={styles.rows}><article><div><strong>{venueText(location.contactName)}</strong><small>{venueText(location.contactPhone)} {venueText(location.contactEmail)}</small></div></article></div> : null}</aside>
      </section>
    </main>
  </OfficialProductShellV2>;
}
