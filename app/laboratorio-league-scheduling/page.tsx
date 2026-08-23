import Link from "next/link";
import { LeagueSchedulingClient } from "../_components/league-scheduling-client";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { GamePageHeader, MetricTile } from "../_components/official-ui-v2-primitives";
import { leagueSchedulingFixture, leagueSchedulingScenarios, type LeagueSchedulingScenario } from "./fixtures";
import styles from "./page.module.css";

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function LeagueSchedulingLabPage({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const query = await searchParams;
  const requested = first(query.scenario);
  const scenario = leagueSchedulingScenarios.some(([id]) => id === requested)
    ? requested as LeagueSchedulingScenario
    : "";
  if (scenario) return <LeagueSchedulingClient previewData={leagueSchedulingFixture(scenario)} surface="workbench" />;
  return <OfficialProductShellV2 active="equipo" context={{ detail: "Fixtures locales · flags OFF", eyebrow: "Laboratorio R4B", status: "No productivo", title: "League Scheduling" }}>
    <main className={styles.index} data-mobile-tab="equipo">
      <GamePageHeader eyebrow="League Scheduling R4B" summary="Generación, restricciones, calidad, revisión y publicación canónica sin escribir en Supabase." title="Laboratorio de calendarios" />
      <section className={styles.links}>{leagueSchedulingScenarios.map(([id, label]) => <Link href={`?scenario=${id}`} key={id}><strong>{label}</strong><span>Abrir fixture determinista</span></Link>)}</section>
      <section className={styles.metrics}><MetricTile label="Motor" value="v1" /><MetricTile label="Capacidad" value="32" /><MetricTile label="Resultados" value="0" /><MetricTile label="Standings" value="0" /></section>
    </main>
  </OfficialProductShellV2>;
}
