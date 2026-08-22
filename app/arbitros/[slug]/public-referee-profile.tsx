"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { RefereeProfileCard } from "../../_components/referee-profile-card";
import { GamePageHeader, MetricTile, ProductFeedback, SectionHeader, StatusChip } from "../../_components/official-ui-v2-primitives";
import { refereeArray, refereeModalityLabel, refereeNumber, refereeRecord, refereeText, type RefereeJson } from "../../referee-platform-contract";
import styles from "./public-referee.module.css";

export function PublicRefereeProfile({ previewProfile = null, slug }: { previewProfile?: RefereeJson | null; slug: string }) {
  const [profile, setProfile] = useState<RefereeJson | null>(previewProfile);
  const [loading, setLoading] = useState(!previewProfile);

  useEffect(() => {
    if (previewProfile) return;
    let active = true;
    void fetch(`/api/referees/public/${encodeURIComponent(slug)}`, { cache: "no-store" })
      .then(async (response) => ({ body: await response.json() as { profile?: unknown }, ok: response.ok }))
      .then(({ body, ok }) => { if (active) setProfile(ok ? refereeRecord(body.profile) : null); })
      .catch(() => { if (active) setProfile(null); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [previewProfile, slug]);

  const shellContext = {
    detail: loading ? "Consultando estado canónico" : profile ? refereeText(profile.availabilityStatus).replaceAll("_", " ") : "Producto no disponible",
    eyebrow: "Mercado · Árbitros",
    status: previewProfile ? "Solo visual" : "Vista pública",
    title: refereeText(profile?.displayName) || "Perfil arbitral",
  };

  if (loading) return <OfficialProductShellV2 active="mercado" context={shellContext}><main className={styles.page} data-mobile-tab="mercado"><p className={styles.state}>Cargando ficha arbitral...</p></main></OfficialProductShellV2>;
  if (!profile) return <OfficialProductShellV2 active="mercado" context={shellContext}><main className={styles.page} data-mobile-tab="mercado"><section className={styles.unavailable}><span>Perfil no disponible</span><h1>Ficha arbitral cerrada</h1><Link href="/mercado?tab=arbitros">Volver a Mercado</Link></section></main></OfficialProductShellV2>;

  const windows = refereeArray(profile.availabilityWindows);
  const clubs = refereeArray(profile.clubs);
  const areas = refereeArray(profile.areas);
  const modalities = refereeArray(profile.modalities);
  const statistics = refereeRecord(profile.statistics);
  return (
    <OfficialProductShellV2 active="mercado" context={shellContext}>
    <main className={styles.page} data-mobile-tab="mercado">
      <GamePageHeader actions={<Link href="/mercado?tab=arbitros">Volver a Mercado</Link>} eyebrow="Ficha pública" summary="Información arbitral publicada por su titular y confirmada por el servidor." title={refereeText(profile.displayName)} />
      <div className={styles.layout}>
        <div className={styles.cardStage}><RefereeProfileCard adaptive profile={profile} /></div>
        <div aria-label="Detalle del perfil arbitral" className={styles.details} role="region" tabIndex={0}>
          <section><SectionHeader eyebrow="Perfil arbitral" title={refereeText(profile.displayName)} /><p>{refereeText(profile.experienceSummary) || refereeText(profile.bio) || "Sin presentación pública."}</p><div className={styles.metrics}><MetricTile label="Partidos concluidos" value={refereeNumber(statistics.matchesCompleted)} /><MetricTile label="Modalidades" value={modalities.length} /><MetricTile label="Zonas" value={areas.length} /></div></section>
          <section><SectionHeader eyebrow="Cobertura" title="Modalidades y zonas" /><div className={styles.rows}>{modalities.map((item) => <span key={refereeText(item.modality)}>{refereeModalityLabel(item.modality)}</span>)}{areas.map((item, index) => <span key={`${refereeText(item.generalArea)}:${index}`}>{refereeText(item.generalArea) || refereeText(item.municipality)}</span>)}</div></section>
          <section className={styles.discipline}><SectionHeader eyebrow="R5 pendiente" title="Estadísticas disciplinarias" /><StatusChip tone="neutral">NOT_AVAILABLE</StatusChip><p>Disponibles cuando se active el motor de disciplina.</p></section>
        </div>
        <aside className={styles.availability}>
          <section><SectionHeader eyebrow="Agenda" title="Disponibilidad publicada" />{windows.length ? <div className={styles.rows}>{windows.map((item, index) => <span key={index}>Día {refereeText(item.weekday)} · {refereeText(item.startLocalTime)}-{refereeText(item.endLocalTime)}</span>)}</div> : <ProductFeedback tone="info">Solo se ha publicado el estado general de disponibilidad.</ProductFeedback>}</section>
          <section><SectionHeader eyebrow="Red" title="Clubs visibles" />{clubs.length ? <div className={styles.rows}>{clubs.map((item, index) => <span key={`${refereeText(item.slug)}:${index}`}>{refereeText(item.name)} · {refereeText(item.relationshipType)}</span>)}</div> : <p>Sin Clubs visibles.</p>}</section>
          <section className={styles.publicState}><StatusChip tone={refereeText(profile.verificationStatus) === "verified" ? "success" : "neutral"}>{refereeText(profile.verificationStatus) === "verified" ? "Verificado" : "No verificado"}</StatusChip><p>Las propuestas se envían desde un partido y requieren autoridad de owner.</p></section>
        </aside>
        </div>
    </main>
    </OfficialProductShellV2>
  );
}
