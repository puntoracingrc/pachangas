"use client";

import { useEffect, useMemo, useState } from "react";
import { venueStatusLabel } from "../venue-operations-contract";
import {
  assertDemoWorldV34FieldOperations,
  type DemoWorldV34FieldOperations,
  type DemoWorldV34Perspective,
  type DemoWorldV34PresentationManifest,
} from "./demo-world-v3-4-contract";
import styles from "./demo-world-v3-4-field-operations.module.css";

const perspectiveLabels: Record<DemoWorldV34Perspective, string> = {
  "club-booking-manager": "Gestor de reservas",
  "league-organizer": "Organizador",
  "platform-reviewer": "Revisor de plataforma",
  player: "Jugador",
  referee: "Árbitro",
  "team-owner": "Owner de equipo",
};

export function DemoWorldV34FieldOperations({ manifest }: { manifest: DemoWorldV34PresentationManifest }) {
  const [data, setData] = useState<DemoWorldV34FieldOperations | null>(null);
  const [error, setError] = useState("");
  const [perspective, setPerspective] = useState<DemoWorldV34Perspective>("team-owner");
  const [selectedVenueId, setSelectedVenueId] = useState("demo_venue_centre");

  useEffect(() => {
    let active = true;
    void fetch(manifest.fieldOperations.path, { cache: "force-cache", credentials: "same-origin" })
      .then(async (response) => {
        if (!response.ok) throw new Error("No se pudo cargar Field Operations.");
        return assertDemoWorldV34FieldOperations(await response.json() as DemoWorldV34FieldOperations);
      })
      .then((value) => { if (active) setData(value); })
      .catch((caught) => { if (active) setError(caught instanceof Error ? caught.message : "No se pudo cargar Field Operations."); });
    return () => { active = false; };
  }, [manifest.fieldOperations.path]);

  const stories = useMemo(() => data?.stories.filter((story) => story.perspective === perspective) ?? [], [data, perspective]);
  const selectedVenue = data?.venues.find((venue) => venue.id === selectedVenueId) ?? data?.venues[0];
  const pitches = data?.pitches.filter((pitch) => pitch.venueId === selectedVenue?.id) ?? [];

  if (error) return <section className={styles.error}><strong>Field Operations no disponible</strong><p>{error}</p></section>;
  if (!data || !selectedVenue) return <section className={styles.loading} role="status">Cargando Campos y reservas ficticias...</section>;

  return (
    <div className={styles.shell} data-demo-field-operations="v3.4">
      <header className={styles.hero}>
        <div><span>Mundo Demo V3.4</span><h1>Campos y reservas</h1><p>Operación ficticia completa con snapshots canónicos. Esta superficie no ejecuta RPC ni modifica datos remotos.</p></div>
        <div className={styles.proof}><strong>{data.counts.venues}</strong><small>instalaciones</small><strong>{data.counts.pitches}</strong><small>campos</small><strong>{data.counts.stories}</strong><small>historias</small></div>
      </header>

      <section className={styles.perspectives} aria-label="Perspectiva de Field Operations">
        {(Object.keys(perspectiveLabels) as DemoWorldV34Perspective[]).map((id) => <button aria-current={perspective === id ? "page" : undefined} key={id} type="button" onClick={() => setPerspective(id)}>{perspectiveLabels[id]}</button>)}
      </section>

      <div className={styles.layout}>
        <aside className={styles.venueList}>
          <span>Instalaciones</span>
          {data.venues.map((venue) => <button aria-current={selectedVenue.id === venue.id ? "page" : undefined} key={venue.id} type="button" onClick={() => setSelectedVenueId(venue.id)}><strong>{venue.name}</strong><small>{venue.generalArea}</small><b>{venue.visibility === "PUBLIC" ? "Pública" : "Privada"}</b></button>)}
        </aside>

        <main className={styles.workspace}>
          <section className={styles.venueHero}>
            <div><span>{selectedVenue.visibility === "PUBLIC" ? "Perfil público consentido" : "Acceso privado"}</span><h2>{selectedVenue.name}</h2><p>{selectedVenue.generalArea} · {selectedVenue.services.join(" · ")}</p></div>
            <b>{selectedVenue.publicationConsent ? "Consentimiento activo" : "Ubicación protegida"}</b>
          </section>

          <section className={styles.pitchGrid} aria-label={`Campos de ${selectedVenue.name}`}>
            {pitches.map((pitch) => <article data-status={pitch.status} key={pitch.id}><header><div><span>{pitch.environment === "INDOOR" ? "Indoor" : "Exterior"}</span><h3>{pitch.name}</h3></div><b>{pitch.status === "ACTIVE" ? "Activo" : "Mantenimiento"}</b></header><p>{pitch.modalities.map((item) => item === "FUTSAL" ? "Fútbol sala" : item === "F11" ? "Fútbol 11" : "Fútbol 7").join(" · ")}</p><small>{pitch.surface === "PARQUET" ? "Parquet" : "Césped artificial"} · {pitch.availability}</small></article>)}
          </section>

          <section className={styles.storySection}>
            <header><div><span>Flujo por rol</span><h2>{perspectiveLabels[perspective]}</h2></div><small>{stories.length} casos destacados</small></header>
            <div className={styles.storyRail}>{stories.map((story) => <article data-state={story.state} key={story.id}><span>{story.state.replaceAll("_", " ")}</span><h3>{story.title}</h3><p>{story.summary}</p>{story.reservationStatus ? <b>{venueStatusLabel(story.reservationStatus)}</b> : null}{story.matchBinding ? <small>{story.matchBinding.lineage.join(" → ")} · {story.matchBinding.status}</small> : null}{story.paymentKind ? <small>{story.paymentKind.replaceAll("_", " ")} · {data.payment.notice}</small> : null}</article>)}</div>
          </section>
        </main>
      </div>

      <footer className={styles.integrity}>
        <span><strong>0</strong> overlaps confirmados</span><span><strong>0</strong> escrituras remotas</span><span><strong>0</strong> llamadas Stripe</span><span><strong>{data.integrity.refereeReconfirmationCases}</strong> reconfirmación arbitral</span><p>{data.payment.notice}</p>
      </footer>
    </div>
  );
}
