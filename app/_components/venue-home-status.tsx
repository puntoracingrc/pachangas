"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "../supabaseClient";
import { venueNumber, venueRecord, type VenueJson } from "../venue-operations-contract";
import styles from "./venue-home-status.module.css";

type Notice = { detail: string; href: string; id: string; label: string; value: number };

export function VenueHomeStatus() {
  const [data, setData] = useState<VenueJson | null>(null);

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let timer: number | null = null;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(({ data: sessionData }) => {
      const token = sessionData.session?.access_token;
      if (!active || !token) return;
      const reconcile = (delay = 0) => {
        if (timer) window.clearTimeout(timer);
        timer = window.setTimeout(() => {
          void fetch("/api/venues/home", { cache: "no-store", headers: { Authorization: "Bearer " + token } })
            .then(async (response) => response.ok ? response.json() as Promise<VenueJson> : null)
            .then((value) => { if (active && value) setData(value); });
        }, delay);
      };
      reconcile();
      channel = client.channel("venue-home-status")
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "pachanga_venue_invalidations" }, () => reconcile(120))
        .subscribe((status) => { if (status === "SUBSCRIBED") reconcile(300); });
    });
    return () => {
      active = false;
      if (timer) window.clearTimeout(timer);
      if (channel) void client.removeChannel(channel);
    };
  }, []);

  const notices = useMemo(() => {
    const team = venueRecord(data?.teamOwner);
    const club = venueRecord(data?.clubBookingManager);
    const organizer = venueRecord(data?.competitionOrganizer);
    const result: Notice[] = [];
    if (team.visible) {
      result.push({ detail: "Contrapropuestas pendientes", href: "/reservas", id: "team-counter", label: "Reservas", value: venueNumber(team.pendingCounterproposals) });
      result.push({ detail: "Reservas por confirmar", href: "/reservas", id: "team-confirm", label: "Confirmar", value: venueNumber(team.reservationsToConfirm) });
      result.push({ detail: "Partidos sin campo", href: "/?mobile=partido", id: "team-venue", label: "Campo", value: venueNumber(team.matchesWithoutVenue) });
    }
    if (club.visible) {
      result.push({ detail: "Solicitudes nuevas", href: "/clubes/gestionar/reservas", id: "club-requests", label: "Club", value: venueNumber(club.newRequests) });
      result.push({ detail: "Holds próximos a expirar", href: "/clubes/gestionar/reservas", id: "club-holds", label: "Holds", value: venueNumber(club.holdsExpiring) });
      result.push({ detail: "Conflictos y reservas de hoy", href: "/clubes/gestionar/reservas", id: "club-health", label: "Operación", value: venueNumber(club.conflicts) + venueNumber(club.reservationsToday) });
    }
    if (organizer.visible) {
      result.push({ detail: "Partidos sin Venue", href: "/competiciones", id: "organizer-venue", label: "Competición", value: venueNumber(organizer.matchesWithoutVenue) });
      result.push({ detail: "Reservas canceladas", href: "/competiciones", id: "organizer-cancel", label: "Revisar", value: venueNumber(organizer.cancelledReservations) });
      result.push({ detail: "Cambios de sede", href: "/competiciones", id: "organizer-change", label: "R4D", value: venueNumber(organizer.venueChanges) });
    }
    return result.filter((item) => item.value > 0).slice(0, 3);
  }, [data]);

  if (!notices.length) return null;
  return <div className={styles.notice} aria-label="Estado de Campos y reservas">{notices.map((notice) => <Link data-urgent={notice.value > 0} href={notice.href} key={notice.id}><span>{notice.label}</span><strong>{notice.value} · {notice.detail}</strong><small>Estado confirmado por PostgreSQL</small></Link>)}</div>;
}
