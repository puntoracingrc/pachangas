import {
  PROVINCIAL_RANKING_REASON_LABELS,
  provincialRankingStatusText,
  type ProvincialOwnRank,
  type ProvincialRankingPayload,
} from "./provincial-ranking-contract";
import styles from "./ranking.module.css";

export function ProvincialRankingBoard({
  embedded = false,
  loading = false,
  ownRank,
  ranking,
}: {
  embedded?: boolean;
  loading?: boolean;
  ownRank: ProvincialOwnRank | null;
  ranking: ProvincialRankingPayload | null;
}) {
  const leader = ranking?.items[0] ?? null;
  const availabilityMessage = PROVINCIAL_RANKING_REASON_LABELS[ranking?.reason ?? ""]
    ?? "La clasificación provincial se abrirá cuando el piloto esté listo.";
  const ownMessage = ownRank?.reasonCodes?.map((code) => PROVINCIAL_RANKING_REASON_LABELS[code] ?? code).join(" · ")
    || PROVINCIAL_RANKING_REASON_LABELS[ownRank?.reason ?? ""];

  return (
    <div className={styles.layout} data-embedded={embedded || undefined}>
      <section className={styles.ownPanel} data-own-ranking="first">
        <header><span>Mi posición</span><b data-state={ownRank?.eligibilityState}>{provincialRankingStatusText(ownRank?.eligibilityState)}</b></header>
        {ownRank?.available ? <div className={styles.ownSummary}>
          <div className={styles.ownScore}>
            <strong>{ownRank.position ? `#${ownRank.position}` : "--"}</strong>
            <output>{ownRank.score ?? 0}</output>
          </div>
          <div>
            <h2>{ownRank.displayName}</h2>
            <p>{ownRank.validChallenges} retos válidos · {ownRank.logicalOpponents} rivales</p>
            {ownMessage && <small>{ownMessage}</small>}
          </div>
        </div> : <div className={styles.ownEmpty}>{ownMessage ?? "Inicia sesión para consultar tu posición."}</div>}
      </section>

      <section className={styles.rankingPanel} aria-busy={loading}>
        <header>
          <div><span>Clasificación oficial</span><h2>Top {ranking?.territory?.provinceName ?? "provincial"}</h2></div>
          <strong>{ranking?.pagination?.total ?? ranking?.items.length ?? 0} jugadores</strong>
        </header>
        {loading && !ranking ? <div className={styles.empty}>Actualizando clasificación...</div>
          : !ranking?.available ? <div className={styles.empty}>{availabilityMessage}</div>
            : <ol className={styles.list}>
              {ranking.items.map((item) => (
                <li key={item.entryKey} data-podium={item.position <= 3 ? item.position : undefined}>
                  <b>{item.position}</b>
                  <div className={styles.player}>
                    <strong>{item.displayName}</strong>
                    <span>{item.validChallenges} retos · {item.logicalOpponents} rivales</span>
                  </div>
                  <div className={styles.components} aria-label="Componentes del Season Score">
                    <span title="Calidad">CAL {item.components.quality}</span>
                    <span title="Competición">COM {item.components.competition}</span>
                    <span title="Oposición">OPO {item.components.opposition}</span>
                  </div>
                  <output>{item.score}</output>
                </li>
              ))}
            </ol>}
      </section>

      <aside className={styles.side}>
        <section className={styles.formulaPanel}>
          <span>Season Score V3</span>
          <h2>Una puntuación, tres señales</h2>
          <dl>
            <div><dt>Calidad</dt><dd>55%</dd></div>
            <div><dt>Competición</dt><dd>30%</dd></div>
            <div><dt>Oposición</dt><dd>15%</dd></div>
          </dl>
          {leader && <p>Líder actual: <strong>{leader.displayName}</strong> con {leader.score} puntos.</p>}
        </section>
      </aside>
    </div>
  );
}
