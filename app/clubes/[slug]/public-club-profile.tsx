"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "../../supabaseClient";
import styles from "./public-club.module.css";

type JsonRecord = Record<string, unknown>;
function record(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function array(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function text(value: unknown) { return typeof value === "string" ? value : ""; }

export function PublicClubProfile({ slug }: { slug: string }) {
  const [club, setClub] = useState<JsonRecord | null>(null);
  const [loading, setLoading] = useState(Boolean(supabase));

  useEffect(() => {
    let active = true;
    if (!supabase) return;
    void supabase.rpc("get_pachanga_public_club_v1", { target_slug: slug }).then((result) => {
      if (!active) return;
      setClub(result.error ? null : record(result.data));
      setLoading(false);
    });
    return () => { active = false; };
  }, [slug]);

  if (loading) return <main className={styles.page}><p className={styles.state}>Cargando club...</p></main>;
  if (!club || !text(club.name)) {
    return <main className={styles.page}><section className={styles.unavailable}><span>Club no disponible</span><h1>Este perfil no es público</h1><p>Puede estar desactivado, pendiente de revisión o publicado solo para sus miembros.</p><Link href="/">Volver a Pachangas IQ</Link></section></main>;
  }

  const area = record(club.generalArea);
  const teams = array(club.teams);
  const logoAsset = text(club.logoAsset);
  const localLogoAsset = logoAsset.startsWith("/") ? logoAsset : "";
  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <Link href="/" aria-label="Pachangas IQ"><Image src="/icon-192.png" alt="" width={42} height={42} unoptimized /></Link>
        <span>Club verificado por Pachangas IQ</span>
      </header>
      <section className={styles.identity}>
        <div className={styles.logo} aria-hidden={!localLogoAsset}>
          {localLogoAsset ? <Image src={localLogoAsset} alt="" fill sizes="120px" /> : <span>{text(club.name).slice(0, 2).toUpperCase()}</span>}
        </div>
        <div>
          <p>{text(club.clubType).replaceAll("_", " ")}</p>
          <h1>{text(club.name)}</h1>
          <span>{[text(area.municipality), text(area.province), text(area.countryCode)].filter(Boolean).join(" · ")}</span>
        </div>
        <div className={styles.badges}>
          {club.verified ? <strong>Verificado</strong> : null}
          {club.partner ? <strong>Partner</strong> : null}
        </div>
      </section>
      {text(club.description) ? <p className={styles.description}>{text(club.description)}</p> : null}
      <section className={styles.teams}>
        <h2>Equipos vinculados</h2>
        {teams.length ? <div>{teams.map((team, index) => <article key={`${text(team.name)}:${index}`}><strong>{text(team.name)}</strong><span>{text(team.relationshipType)}</span></article>)}</div> : <p>Este club todavía no muestra equipos públicos.</p>}
      </section>
    </main>
  );
}
