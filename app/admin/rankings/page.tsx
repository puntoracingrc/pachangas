import Link from "next/link";
import { DataTable, PageHeader, Panel, StatusBadge } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import styles from "../platform-admin.module.css";

const contracts = [
  { key: "rating_v2", label: "Rating V2 y perfiles universales", state: "PRODUCTIVO", source: "pachanga_player_profiles", note: "Carta, facetas y fiabilidad canónicas." },
  { key: "season_score_v3", label: "Season Score V3", state: "LAB", source: "season-ranking-lab", note: "Motor validado en laboratorio, no ranking público productivo." },
  { key: "provincial_ranking", label: "Ranking provincial", state: "LAB", source: "/laboratorio-ranking-provincial", note: "Piloto visual y territorial, sin autoridad productiva." },
  { key: "territory_awards", label: "Premios territoriales", state: "OFF", source: "territory-award-readiness", note: "No concede trofeos ni rewards." },
];

export default async function PlatformRankingsPage() {
  const session = await requirePlatformPage("rankings.read");
  return <><PageHeader title="Rankings y TOPS" subtitle="El panel distingue producto, laboratorio y apagado; no presenta resultados sintéticos como clasificación oficial." actions={hasPlatformCapability(session.access, "labs.read") ? <Link className={styles.secondaryButton} href="/laboratorio-ranking-provincial">Abrir laboratorio</Link> : undefined} />
    <Panel><DataTable label="Contratos de ranking"><thead><tr><th>Sistema</th><th>Estado</th><th>Fuente</th><th>Lectura operativa</th></tr></thead><tbody>{contracts.map((item) => <tr key={item.key}><td>{item.label}<small>{item.key}</small></td><td><StatusBadge tone={item.state === "PRODUCTIVO" ? "good" : item.state === "LAB" ? "info" : "muted"}>{item.state}</StatusBadge></td><td><code className={styles.identifier}>{item.source}</code></td><td>{item.note}</td></tr>)}</tbody></DataTable></Panel>
    <Panel title="Read model productivo"><p className={styles.emptyState}>AUSENTE: main no contiene todavía un read model PostgreSQL productivo de Season Score/TOPS. El Control Center no recalcula ni persiste resultados de laboratorio.</p></Panel>
  </>;
}
