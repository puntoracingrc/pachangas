"use client";

import { useEffect, useMemo, useState } from "react";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import type { ProductContextOption } from "../_components/product-context-selector";
import {
  TeamChallengesPanel,
  type TeamChallengesShellState,
} from "../mercado/team-challenges-panel";
import {
  challengeRouteSearch,
  parseChallengeRoute,
  type ChallengeActiveFilter,
  type ChallengeMainView,
  type ChallengeRouteState,
} from "../team-challenges-ui-contract";
import styles from "./retos.module.css";

const emptyRoute: ChallengeRouteState = {
  challengeId: "",
  creating: false,
  filter: "all",
  legacy: false,
  matchChallengeId: "",
  rivalCode: "",
  view: "active",
};

const activeFilters: Array<{ id: ChallengeActiveFilter; label: string }> = [
  { id: "all", label: "Todos" },
  { id: "received", label: "Recibidos" },
  { id: "sent", label: "Enviados" },
];

export default function ChallengesPage() {
  const [route, setRoute] = useState<ChallengeRouteState>(emptyRoute);
  const [shellState, setShellState] = useState<TeamChallengesShellState | null>(null);
  const [requestedGroupId, setRequestedGroupId] = useState("");

  useEffect(() => {
    const restore = () => {
      const next = parseChallengeRoute(window.location.search);
      setRoute(next);
      if (next.legacy) {
        window.history.replaceState(null, "", `${window.location.pathname}?${challengeRouteSearch({ ...next, legacy: false })}`);
      }
    };
    restore();
    window.addEventListener("popstate", restore);
    return () => window.removeEventListener("popstate", restore);
  }, []);

  function navigate(next: ChallengeRouteState, replace = false) {
    const normalized = { ...next, legacy: false };
    const url = `${window.location.pathname}?${challengeRouteSearch(normalized)}`;
    if (replace) window.history.replaceState(null, "", url);
    else window.history.pushState(null, "", url);
    setRoute(normalized);
    window.scrollTo({ behavior: "smooth", top: 0 });
  }

  function selectView(view: ChallengeMainView) {
    navigate({ ...route, challengeId: "", creating: false, matchChallengeId: "", rivalCode: "", view });
  }

  function selectFilter(filter: ChallengeActiveFilter) {
    navigate({ ...route, challengeId: "", filter, matchChallengeId: "", view: "active" });
  }

  const selectedMembership = shellState?.memberships.find((membership) => membership.groupId === shellState.selectedGroupId) ?? null;
  const contextOptions = useMemo<ProductContextOption[]>(() => shellState?.memberships.map((membership) => ({
    detail: "Retos y partidos contra otros equipos",
    id: membership.groupId,
    role: membership.role,
    status: membership.role === "player" ? "Jugador" : "Gestión de equipo",
    title: membership.name,
    type: "team",
  })) ?? [], [shellState?.memberships]);
  const perspective = selectedMembership?.role === "owner"
    ? "team-owner"
    : selectedMembership?.role === "admin"
      ? "team-admin"
      : "player";
  const matchMode = Boolean(route.matchChallengeId);

  return (
    <OfficialProductShellV2
      active={matchMode ? "partido" : "retos"}
      context={{
        detail: "Retos y partidos contra otros equipos",
        id: selectedMembership?.groupId,
        status: selectedMembership?.role === "player" ? "Jugador" : "Equipo activo",
        title: selectedMembership?.name ?? "Tu espacio de jugador",
        type: selectedMembership ? "team" : "profile",
      }}
      contextOptions={contextOptions.length ? contextOptions : undefined}
      onContextChange={(groupId) => setRequestedGroupId(groupId)}
      perspective={perspective}
    >
      <main className={styles.page} data-mobile-tab={matchMode ? "partido" : "retos"} data-retos-view={route.view}>
        <header className={styles.header}>
          <div>
            <h1>{matchMode ? "Partido acordado" : "Retos"}</h1>
            <p>{matchMode ? "Partido nacido de un reto entre equipos." : "Organiza un partido contra otro equipo."}</p>
          </div>
          {matchMode ? (
            <button type="button" onClick={() => navigate({ ...route, matchChallengeId: "", view: "active" })}>Volver a Retos</button>
          ) : shellState?.canManage ? (
            <button type="button" onClick={() => navigate({ ...route, challengeId: "", creating: true, matchChallengeId: "", rivalCode: "", view: "active" })}>+ Retar equipo</button>
          ) : null}
        </header>

        {!matchMode ? (
          <>
            <nav className={styles.tabs} aria-label="Vistas de retos">
              <button aria-current={route.view === "active" ? "page" : undefined} className={route.view === "active" ? styles.active : ""} type="button" onClick={() => selectView("active")}>Activos</button>
              <button aria-current={route.view === "history" ? "page" : undefined} className={route.view === "history" ? styles.active : ""} type="button" onClick={() => selectView("history")}>Historial</button>
            </nav>
            {route.view === "active" && !route.creating && !route.challengeId ? (
              <nav className={styles.filters} aria-label="Filtrar retos activos">
                {activeFilters.map((filter) => (
                  <button aria-pressed={route.filter === filter.id} key={filter.id} type="button" onClick={() => selectFilter(filter.id)}>{filter.label}</button>
                ))}
              </nav>
            ) : null}
          </>
        ) : null}

        <TeamChallengesPanel
          activeFilter={route.filter}
          challengeId={route.challengeId}
          creating={route.creating}
          initialTeamCode={route.rivalCode}
          matchChallengeId={route.matchChallengeId}
          onCloseCreate={() => navigate({ ...route, creating: false, rivalCode: "", view: "active" })}
          onCloseDetail={() => navigate({ ...route, challengeId: "", view: route.view })}
          onOpenChallenge={(challengeId) => navigate({ ...route, challengeId, creating: false, matchChallengeId: "" })}
          onOpenMatch={(matchChallengeId) => navigate({ ...route, challengeId: "", creating: false, matchChallengeId, view: "active" })}
          onShellState={setShellState}
          onStartCreate={() => navigate({ ...route, challengeId: "", creating: true, matchChallengeId: "", rivalCode: "", view: "active" })}
          requestedGroupId={requestedGroupId}
          view={route.view}
        />
      </main>
    </OfficialProductShellV2>
  );
}
