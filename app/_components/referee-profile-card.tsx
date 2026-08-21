import Image from "next/image";
import {
  refereeArray,
  refereeAvailabilityLabel,
  refereeModalityLabel,
  refereeNumber,
  refereeRecord,
  refereeText,
  type RefereeJson,
} from "../referee-platform-contract";
import styles from "./referee-profile-card.module.css";

export function RefereeProfileCard({ compact = false, profile }: { compact?: boolean; profile: RefereeJson }) {
  const modalities = refereeArray(profile.modalities);
  const areas = refereeArray(profile.areas);
  const clubs = refereeArray(profile.clubs);
  const statistics = refereeRecord(profile.statistics);
  const name = refereeText(profile.displayName) || "Árbitro";
  const initials = name.split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("");
  const avatar = refereeText(profile.avatar);

  return (
    <article className={styles.card} data-compact={compact || undefined} aria-label={`Ficha arbitral de ${name}`}>
      <header className={styles.header}>
        <span>Árbitro</span>
        <strong data-verified={refereeText(profile.verificationStatus) === "verified" || undefined}>
          {refereeText(profile.verificationStatus) === "verified" ? "Verificado" : "No verificado"}
        </strong>
      </header>
      <div className={styles.identity}>
        <div className={styles.avatar}>
          {avatar ? <Image src={avatar} alt="" width={112} height={112} unoptimized /> : <span>{initials || "AR"}</span>}
        </div>
        <div>
          <h2>{name}</h2>
          <p>{refereeAvailabilityLabel(profile.availabilityStatus)}</p>
        </div>
      </div>
      <dl className={styles.metrics}>
        <div><dt>Partidos</dt><dd>{refereeNumber(statistics.matchesCompleted)}</dd></div>
        <div><dt>Modalidades</dt><dd>{modalities.length}</dd></div>
        <div><dt>Zonas</dt><dd>{areas.length}</dd></div>
        <div><dt>Clubs</dt><dd>{clubs.length}</dd></div>
      </dl>
      <div className={styles.tags}>
        {modalities.slice(0, compact ? 3 : 5).map((item) => <span key={refereeText(item.modality)}>{refereeModalityLabel(item.modality)}</span>)}
        {areas.slice(0, compact ? 2 : 4).map((item, index) => (
          <span key={`${refereeText(item.generalArea)}:${index}`}>{refereeText(item.generalArea) || refereeText(item.municipality)}</span>
        ))}
      </div>
      {!compact ? <p className={styles.bio}>{refereeText(profile.bio) || refereeText(profile.experienceSummary)}</p> : null}
      <footer>
        <span>{refereeText(profile.experienceSinceYear) ? `Desde ${refereeText(profile.experienceSinceYear)}` : "Experiencia declarada"}</span>
        <span>{refereeText(profile.slug) ? `@${refereeText(profile.slug)}` : "Perfil privado"}</span>
      </footer>
    </article>
  );
}
