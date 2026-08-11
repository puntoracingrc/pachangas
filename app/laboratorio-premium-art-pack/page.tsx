import Image from "next/image";
import { PlayerCardView } from "../_components/player-card-view";
import { TeamShieldView } from "../_components/team-shield-view";
import { TEAM_SHIELD_RENDER_CATALOG } from "../team-shield-cosmetics-catalog";
import { TEAM_SHIELD_DEFAULT_CONFIG, type TeamShieldConfig } from "../team-shield-contract";
import { PREMIUM_ART_PACK_V1, type PremiumArtProposal } from "./premium-art-pack-catalog";
import styles from "./page.module.css";

const categories = ["Símbolo", "Corona", "Estrella", "Laureles", "Banner", "Material", "Efecto"] as const;
const facets = [
  { key: "rit", label: "RIT", value: 78 },
  { key: "tir", label: "TIR", value: 74 },
  { key: "pas", label: "PAS", value: 82 },
  { key: "reg", label: "REG", value: 80 },
  { key: "def", label: "DEF", value: 72 },
  { key: "fis", label: "FÍS", value: 76 },
];

const rewardShields: Array<{ label: string; config: TeamShieldConfig }> = [
  {
    label: "Primer Reto · Cobre",
    config: { ...TEAM_SHIELD_DEFAULT_CONFIG, borderKey: "team.shield.border.copper", initials: "1R" },
  },
  {
    label: "10 Retos · Banner",
    config: { ...TEAM_SHIELD_DEFAULT_CONFIG, bottomOrnamentKey: "team.shield.ornament.banner", initials: "10" },
  },
  {
    label: "25 partidos · Laureles",
    config: { ...TEAM_SHIELD_DEFAULT_CONFIG, initials: "25", sideOrnamentKey: "team.shield.ornament.laurels" },
  },
  {
    label: "50 partidos · Plata",
    config: { ...TEAM_SHIELD_DEFAULT_CONFIG, borderKey: "team.shield.border.silver", initials: "50" },
  },
  {
    label: "Primera portería a cero · Edge Glow",
    config: { ...TEAM_SHIELD_DEFAULT_CONFIG, effectKey: "team.shield.effect.edge_glow", initials: "0" },
  },
];

function ProposalVisual({ proposal }: { proposal: PremiumArtProposal }) {
  if (proposal.asset) {
    return (
      <Image
        alt={`Estudio visual ${proposal.name}`}
        className={styles.asset}
        height={220}
        priority={proposal.id === "crown-elite" || proposal.id === "star-medallion"}
        src={proposal.asset}
        width={260}
      />
    );
  }
  if (proposal.visual === "monogram") return <strong className={styles.monogram}>PIQ</strong>;
  if (proposal.visual === "star-trio") return <span className={styles.starTrio}>★ <b>★</b> ★</span>;
  if (proposal.visual === "plate") return <span className={styles.plate}>IQ TEAM</span>;
  return <span aria-hidden="true" className={styles.cssArt} data-visual={proposal.visual} />;
}

export default function PremiumArtPackLabPage() {
  const maintained = PREMIUM_ART_PACK_V1.filter((item) => item.decision === "MANTENER").length;
  const reviewed = PREMIUM_ART_PACK_V1.filter((item) => item.decision === "REVISAR").length;

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div>
          <span>Laboratorio · no productivo</span>
          <h1>Premium Art Pack V1</h1>
          <p>Hoja de revisión para símbolos, ornamentos, materiales y LOD. Ninguna propuesta concede propiedad ni cambia desbloqueos.</p>
        </div>
        <dl className={styles.summary}>
          <div><dt>Propuestas</dt><dd>{PREMIUM_ART_PACK_V1.length}</dd></div>
          <div><dt>Mantener</dt><dd>{maintained}</dd></div>
          <div><dt>Revisar</dt><dd>{reviewed}</dd></div>
          <div><dt>Blender</dt><dd>2</dd></div>
        </dl>
      </header>

      <nav className={styles.categoryNav} aria-label="Categorías del Premium Art Pack">
        {categories.map((category) => (
          <a href={`#${category.toLowerCase()}`} key={category}>
            {category}<small>{PREMIUM_ART_PACK_V1.filter((item) => item.type === category).length}</small>
          </a>
        ))}
      </nav>

      <section className={styles.rendererBand} aria-labelledby="renderer-authority">
        <header>
          <div><span>Autoridad de render</span><h2 id="renderer-authority">Cinco desbloqueos protegidos</h2></div>
          <p>Se muestran con <code>TeamShieldView</code> y las claves productivas actuales, sin modificar su mapping.</p>
        </header>
        <div className={styles.rewardRail}>
          {rewardShields.map((study) => (
            <article key={study.label}>
              <TeamShieldView catalog={TEAM_SHIELD_RENDER_CATALOG} config={study.config} size={82} />
              <strong>{study.label}</strong>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.playerBand} aria-labelledby="shared-materials">
        <header>
          <div><span>Material compartible</span><h2 id="shared-materials">Cartas y escudos, misma familia</h2></div>
          <p>Compartir lenguaje material no implica compartir inventario ni propiedad.</p>
        </header>
        <div className={styles.playerRail}>
          {[
            ["fifa-card-bronze", "Barrio", 71],
            ["fifa-card-silver", "Competición", 82],
            ["fifa-card-gold", "Elite", 91],
          ].map(([className, title, score]) => (
            <PlayerCardView
              ariaLabel={`Carta de estudio ${title}`}
              className={`${className} readonly-card`}
              facets={facets}
              key={String(title)}
              meta="18 PJ · 7 Goles"
              name={`ALBERTO ${String(title).toUpperCase()}`}
              position="MC"
              score={score}
              title={<span className={styles.cardTitle}>{title}</span>}
            />
          ))}
        </div>
      </section>

      {categories.map((category) => (
        <section className={styles.catalogSection} id={category.toLowerCase()} key={category}>
          <header>
            <span>{category}</span>
            <strong>{PREMIUM_ART_PACK_V1.filter((item) => item.type === category).length} propuestas</strong>
          </header>
          <div className={styles.contactGrid}>
            {PREMIUM_ART_PACK_V1.filter((item) => item.type === category).map((proposal) => (
              <article className={styles.proposal} data-decision={proposal.decision} key={proposal.id}>
                <div className={styles.visual}><ProposalVisual proposal={proposal} /></div>
                <div className={styles.copy}>
                  <div className={styles.meta}><span>{proposal.collection}</span><b>{proposal.decision}</b></div>
                  <h3>{proposal.name}</h3>
                  <p>{proposal.description}</p>
                  <dl>
                    <div><dt>Técnica</dt><dd>{proposal.technique}</dd></div>
                    <div><dt>Reuso</dt><dd>{proposal.reuse}</dd></div>
                    <div><dt>LOD</dt><dd>{proposal.lod}</dd></div>
                    <div><dt>Peso</dt><dd>{proposal.performance}</dd></div>
                  </dl>
                </div>
              </article>
            ))}
          </div>
        </section>
      ))}

      <section className={styles.lodBand} aria-labelledby="lod-title">
        <header><span>LOD</span><h2 id="lod-title">Laureles a escala real</h2></header>
        <div>
          {[82, 64, 48, 32].map((size) => (
            <figure key={size}>
              <Image alt={`Laureles compactos a ${size}px`} height={size} src="/lab/premium-art-pack-v1/laurels-minted.svg" width={size} />
              <figcaption>{size}px</figcaption>
            </figure>
          ))}
        </div>
      </section>
    </main>
  );
}
