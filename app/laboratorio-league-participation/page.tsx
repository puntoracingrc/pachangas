import Link from "next/link";
import { LeagueParticipationClient, type LeagueParticipationSurface } from "../_components/league-participation-client";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { GamePageHeader, MetricTile } from "../_components/official-ui-v2-primitives";
import { leagueDeskFixture, leagueEntryFixture, leagueMineFixture, leaguePublicFixture, leagueRosterFixture } from "./fixtures";
import styles from "./page.module.css";

const surfaces: Array<{ id: LeagueParticipationSurface | "index"; label: string }> = [
  { id: "index", label: "Índice" },
  { id: "public", label: "Inscripción pública" },
  { id: "mine", label: "Mis competiciones" },
  { id: "desk", label: "Mesa del organizador" },
  { id: "entry", label: "Participación" },
  { id: "roster", label: "Plantilla" },
];

function selected(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "index" : value ?? "index";
}

export default async function LeagueParticipationLabPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams;
  const requested = selected(query.surface);
  const surface = surfaces.some((item) => item.id === requested) ? requested : "index";
  if (surface === "public") return <LeagueParticipationClient previewData={leaguePublicFixture} surface="public" />;
  if (surface === "mine") return <LeagueParticipationClient previewData={leagueMineFixture} surface="mine" />;
  if (surface === "desk") return <LeagueParticipationClient previewData={leagueDeskFixture} surface="desk" />;
  if (surface === "entry") return <LeagueParticipationClient previewData={leagueEntryFixture} surface="entry" />;
  if (surface === "roster") return <LeagueParticipationClient previewData={leagueRosterFixture} surface="roster" />;
  return <OfficialProductShellV2 active="equipo" context={{ detail: "Fixtures aislados · flags OFF", eyebrow: "Laboratorio R4A", status: "No productivo", title: "League Participation" }}>
    <main className={styles.index} data-mobile-tab="equipo">
      <GamePageHeader eyebrow="Integration Gate" summary="Superficies Official UI V2 para revisar desktop, portrait y modo juego horizontal sin escribir en Supabase." title="Inscripciones y plantillas de Liga" />
      <section className={styles.links}>{surfaces.filter((item) => item.id !== "index").map((item) => <Link href={`?surface=${item.id}`} key={item.id}><strong>{item.label}</strong><span>Abrir fixture R4A</span></Link>)}</section>
      <section className={styles.metrics}><MetricTile label="Rounds" value="0" /><MetricTile label="Fixtures" value="0" /><MetricTile label="Canonical Matches" value="0" /><MetricTile label="Standings" value="0" /></section>
    </main>
  </OfficialProductShellV2>;
}
