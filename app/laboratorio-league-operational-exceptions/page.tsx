"use client";

import { useState } from "react";
import { LeagueOperationalExceptionsClient, type LeagueOperationalSurface } from "../_components/league-operational-exceptions-client";
import { leagueOperationalFixtures } from "./fixtures";
import styles from "./page.module.css";

const scenarios: Array<{ id: LeagueOperationalSurface; label: string }> = [
  { id: "match", label: "Partido" },
  { id: "postponements", label: "Aplazamientos" },
  { id: "incidents", label: "Incidencias" },
  { id: "decisions", label: "Decisiones" },
  { id: "my", label: "Solicitudes" },
  { id: "public", label: "Público" },
];

export default function LeagueOperationalExceptionsLabPage() {
  const [scenario, setScenario] = useState<LeagueOperationalSurface>("match");
  return <div className={styles.lab}>
    <nav aria-label="Escenarios R4D"><strong>Laboratorio R4D</strong>{scenarios.map((item) => <button aria-current={scenario === item.id ? "page" : undefined} key={item.id} onClick={() => setScenario(item.id)} type="button">{item.label}</button>)}</nav>
    <LeagueOperationalExceptionsClient competitionId="d4d00000-0000-4000-8000-000000000001" key={scenario} matchId="d4d00000-0000-4000-8000-000000000002" previewData={leagueOperationalFixtures[scenario]} surface={scenario} />
  </div>;
}
