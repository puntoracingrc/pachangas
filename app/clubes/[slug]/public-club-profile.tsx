import Image from "next/image";
import Link from "next/link";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { GamePageHeader, SectionHeader, StatusChip } from "../../_components/official-ui-v2-primitives";
import styles from "./public-club.module.css";

type JsonRecord = Record<string, unknown>;
function record(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function array(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function text(value: unknown) { return typeof value === "string" ? value : ""; }

export function PublicClubProfile({ club }: { club: JsonRecord | null }) {
  const name = text(club?.name) || "Club";
  const context = { detail: club ? "Perfil público" : "No disponible", eyebrow: "Mercado · Clubs", status: "BETA", title: name };
  if (!club) return <OfficialProductShellV2 active="mercado" context={context}><main className={styles.page} data-mobile-tab="mercado"><section className={styles.unavailable}><span>Club no disponible</span><h1>Este perfil no es público</h1><p>Puede estar pendiente de revisión, desactivado o publicado solo para sus miembros.</p><Link href="/clubes">Volver al directorio</Link></section></main></OfficialProductShellV2>;

  const area = record(club.generalArea);
  const teams = array(club.teams);
  const logoAsset = text(club.logoAsset);
  const localLogoAsset = logoAsset.startsWith("/") ? logoAsset : "";
  return <OfficialProductShellV2 active="mercado" context={context}><main className={styles.page} data-mobile-tab="mercado">
    <GamePageHeader actions={<><Link href="/clubes">Directorio</Link><Link href="/clubes/gestionar">Gestionar Clubs</Link></>} eyebrow="Club público · BETA" summary="Información publicada por el Club y confirmada por el servidor central." title={name} />
    <section className={styles.identity}>
      <div className={styles.logo} aria-hidden={!localLogoAsset}>{localLogoAsset ? <Image src={localLogoAsset} alt="" fill sizes="112px" /> : <span>{name.slice(0, 2).toUpperCase()}</span>}</div>
      <div><p>{text(club.clubType).replaceAll("_", " ")}</p><h2>{name}</h2><span>{[text(area.municipality), text(area.province), text(area.countryCode)].filter(Boolean).join(" · ") || text(area.area)}</span></div>
      <div className={styles.badges}>{club.verified ? <StatusChip tone="success">Verificado</StatusChip> : <StatusChip tone="neutral">No verificado</StatusChip>}{club.partner ? <StatusChip tone="warning">Partner</StatusChip> : null}</div>
    </section>
    {text(club.description) ? <p className={styles.description}>{text(club.description)}</p> : null}
    <section className={styles.teams}><SectionHeader eyebrow="Red" title="Equipos visibles" />{teams.length ? <div>{teams.map((team, index) => <article key={`${text(team.name)}:${index}`}><strong>{text(team.name)}</strong><span>{text(team.relationshipType).replaceAll("_", " ")}</span></article>)}</div> : <p>Este Club todavía no muestra equipos públicos.</p>}</section>
  </main></OfficialProductShellV2>;
}
