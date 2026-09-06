import { useState } from "react";
import type { AchievementStats } from "./achievement-gallery-model";
import styles from "./achievement-gallery.module.css";

type Metric = readonly [string, string];
const scopes = [["all", "Todos los partidos"], ["internal", "Pachangas"], ["external", "Retos"]] as const;
const results: Metric[] = [["wins", "Victorias"], ["draws", "Empates"], ["losses", "Derrotas"]];
const opponents: Metric[] = [["distinct_opponents", "Rivales distintos"], ["distinct_opponents_won", "Rivales vencidos"]];
const streaks: Metric[] = [["max_win_streak", "Mejor racha ganando"], ["max_unbeaten_streak", "Mejor racha invicto"]];
const metrics: Record<"team" | "player", Record<"stats" | "records", Metric[]>> = {
  team: {
    stats: [["matches_played", "Partidos"], ...results, ["goals_for", "Goles a favor"], ["goals_against", "Goles en contra"], ["clean_sheets", "Porterías a cero"], ...opponents],
    records: [...streaks, ["big_wins", "Goleadas"], ["close_wins", "Victorias por la mínima"], ["scoreless_draws", "Empates sin goles"]],
  },
  player: {
    stats: [["appearances", "Partidos jugados"], ...results, ["goals", "Goles"], ...opponents],
    records: [...streaks, ["braces", "Dobletes"], ["hat_tricks", "Hat-tricks"], ["pokers", "Pókeres"], ["repokers", "Repókeres"], ["double_hat_tricks", "Dobles hat-tricks"]],
  },
};

export function ProgressionStatistics({ subject, stats, view }: { subject: "team" | "player"; stats: AchievementStats[]; view: "stats" | "records" }) {
  const [scope, setScope] = useState("all");
  const row = stats.find(item => item.match_scope === scope);
  const title = `${view === "stats" ? "Estadísticas" : "Récords"} ${subject === "team" ? "del equipo" : "personales"}`;
  return <section className={styles.statistics} aria-label={title}>
    <header className={styles.statsHeader}><div><h3>{title}</h3><p>{view === "records" ? "Mejores rachas y actuaciones en partidos confirmados." : "Resultados de los partidos confirmados."}</p></div>
      <label>Tipo de partido<select value={scope} onChange={event => setScope(event.target.value)}>{scopes.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
    </header>
    {row ? <dl className={styles.metricCards}>{metrics[subject][view].map(([key, label]) => {
      const raw = row[key];
      const value = typeof raw === "number" && Number.isFinite(raw) ? raw : null;
      return <div key={key}><dt>{label}</dt><dd>{value == null ? "—" : value.toLocaleString("es-ES")}</dd></div>;
    })}</dl> : <p className={styles.message} role="status">{subject === "team" ? "El equipo todavía no tiene datos confirmados para este tipo de partido." : "Todavía no tienes datos confirmados para este tipo de partido."}</p>}
  </section>;
}
