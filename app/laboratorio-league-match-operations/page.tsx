"use client";

import { useState } from "react";
import { LeagueMatchOperationsClient, type LeagueMatchOperationsSurface } from "../_components/league-match-operations-client";
import { leagueMatchOperationsFixtures } from "./fixtures";
import styles from "./page.module.css";

type Scenario = "match" | "result" | "results" | "standings";

const scenarios: Array<{ id: Scenario; label: string; surface: LeagueMatchOperationsSurface }> = [
  { id: "match", label: "Partido", surface: "match" },
  { id: "result", label: "Resultado", surface: "match" },
  { id: "results", label: "Mesa", surface: "results" },
  { id: "standings", label: "Clasificación", surface: "standings" },
];

export default function LeagueMatchOperationsLabPage() {
  const [scenario, setScenario] = useState<Scenario>("match");
  const selected = scenarios.find((item) => item.id === scenario) ?? scenarios[0];
  return <div className={styles.lab}>
    <nav aria-label="Escenarios de laboratorio"><strong>Laboratorio R4C</strong>{scenarios.map((item) => <button aria-current={item.id === scenario ? "page" : undefined} key={item.id} onClick={() => setScenario(item.id)} type="button">{item.label}</button>)}</nav>
    <LeagueMatchOperationsClient
      competitionId="d4c00000-0000-4000-8000-000000000001"
      matchId="d4c00000-0000-4000-8000-000000000004"
      previewData={leagueMatchOperationsFixtures[scenario]}
      stageId="d4c00000-0000-4000-8000-000000000006"
      surface={selected.surface}
    />
  </div>;
}
