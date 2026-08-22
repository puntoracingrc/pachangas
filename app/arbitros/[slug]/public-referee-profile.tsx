"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { RefereeProfileCard } from "../../_components/referee-profile-card";
import { refereeArray, refereeRecord, refereeText, type RefereeJson } from "../../referee-platform-contract";
import styles from "./public-referee.module.css";

export function PublicRefereeProfile({ slug }: { slug: string }) {
  const [profile, setProfile] = useState<RefereeJson | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    void fetch(`/api/referees/public/${encodeURIComponent(slug)}`, { cache: "no-store" })
      .then(async (response) => ({ body: await response.json() as { profile?: unknown }, ok: response.ok }))
      .then(({ body, ok }) => { if (active) setProfile(ok ? refereeRecord(body.profile) : null); })
      .catch(() => { if (active) setProfile(null); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [slug]);

  if (loading) return <main className={styles.page}><p className={styles.state}>Cargando ficha arbitral...</p></main>;
  if (!profile) return <main className={styles.page}><section className={styles.unavailable}><span>Perfil no disponible</span><h1>Ficha arbitral cerrada</h1><Link href="/mercado">Volver a Mercado</Link></section></main>;

  const windows = refereeArray(profile.availabilityWindows);
  const clubs = refereeArray(profile.clubs);
  return (
    <main className={styles.page}>
      <header className={styles.header}><strong>Pachangas IQ</strong><Link href="/mercado?tab=arbitros">Volver a Mercado</Link></header>
      <div className={styles.layout}>
        <RefereeProfileCard profile={profile} />
        <div className={styles.details}>
          <section><h1>{refereeText(profile.displayName)}</h1><p>{refereeText(profile.experienceSummary) || refereeText(profile.bio)}</p></section>
          <section><h2>Disponibilidad publicada</h2>{windows.length ? <div className={styles.rows}>{windows.map((item, index) => <span key={index}>Día {refereeText(item.weekday)} · {refereeText(item.startLocalTime)}-{refereeText(item.endLocalTime)}</span>)}</div> : <p>Estado general publicado.</p>}</section>
          <section><h2>Clubs visibles</h2>{clubs.length ? <div className={styles.rows}>{clubs.map((item, index) => <span key={`${refereeText(item.slug)}:${index}`}>{refereeText(item.name)} · {refereeText(item.relationshipType)}</span>)}</div> : <p>Sin Clubs visibles.</p>}</section>
        </div>
      </div>
    </main>
  );
}
