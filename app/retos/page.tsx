"use client";

import { useEffect, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { TeamChallengesPanel } from "../mercado/team-challenges-panel";
import styles from "./retos.module.css";

type ChallengeView = "history" | "received" | "search" | "sent";

function viewFromSearch(search: string): ChallengeView {
  const value = new URLSearchParams(search).get("vista");
  if (value === "sent" || value === "history" || value === "search") return value;
  return "received";
}

const views: Array<{ id: ChallengeView; label: string }> = [
  { id: "received", label: "Recibidos" },
  { id: "sent", label: "Enviados" },
  { id: "history", label: "Historial" },
];

export default function ChallengesPage() {
  const [view, setView] = useState<ChallengeView>("received");
  const [initialTeamCode, setInitialTeamCode] = useState("");

  useEffect(() => {
    const restore = () => {
      setView(viewFromSearch(window.location.search));
      setInitialTeamCode(new URLSearchParams(window.location.search).get("rival") ?? "");
    };
    restore();
    window.addEventListener("popstate", restore);
    return () => window.removeEventListener("popstate", restore);
  }, []);

  function selectView(nextView: ChallengeView) {
    setView(nextView);
    const params = new URLSearchParams(window.location.search);
    params.set("vista", nextView);
    window.history.pushState(null, "", `${window.location.pathname}?${params.toString()}`);
  }

  return (
    <OfficialProductShellV2
      active="retos"
      context={{ detail: "Desafía a otros equipos", status: "En directo", title: "Tu equipo", type: "team" }}
    >
      <main className={styles.page} data-mobile-tab="retos">
        <header className={styles.header}>
          <div><span>Competición social</span><h1>Retos</h1></div>
          <button type="button" onClick={() => selectView("search")}>Buscar rival</button>
        </header>
        <nav className={styles.tabs} aria-label="Vistas de retos">
          {views.map((item) => (
            <button
              aria-current={view === item.id ? "page" : undefined}
              className={view === item.id ? styles.active : ""}
              key={item.id}
              type="button"
              onClick={() => selectView(item.id)}
            >
              {item.label}
            </button>
          ))}
        </nav>
        {view === "search" ? <button className={styles.back} type="button" onClick={() => selectView("received")}>Volver a recibidos</button> : null}
        <TeamChallengesPanel initialTeamCode={initialTeamCode} key={initialTeamCode || "retos"} view={view} />
      </main>
    </OfficialProductShellV2>
  );
}
