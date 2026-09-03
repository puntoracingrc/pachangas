"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import type { DemoWorldPerspective } from "./demo-world-contract";
import type { DemoWorldV2PrimaryTab } from "./demo-world-v2-contract";
import styles from "./demo-social-quick-review.module.css";

const REVIEW_SESSION_KEY = "pachangas-demo-social-v3h-review";

type QuickReviewJourney = {
  checks: string[];
  firstTime?: boolean;
  id: string;
  label: string;
  objective: string;
  perspectiveId: DemoWorldPerspective["id"];
  perspectiveLabel: string;
  tab: DemoWorldV2PrimaryTab;
};

const journeys: QuickReviewJourney[] = [
  {
    checks: ["Crear un perfil mínimo", "Elegir cómo empezar", "Mantener foto y carta opcionales"],
    firstTime: true,
    id: "new-user",
    label: "Usuario nuevo",
    objective: "Entender Pachangas IQ y empezar sin completar datos innecesarios.",
    perspectiveId: "free-agent",
    perspectiveLabel: "Jugador sin equipo",
    tab: "inicio",
  },
  {
    checks: ["Ver el próximo partido", "Encontrar la asistencia pendiente", "Abrir el contexto del equipo"],
    id: "team-player",
    label: "Jugador con equipo",
    objective: "Saber qué toca hacer al entrar y llegar al partido en un solo paso.",
    perspectiveId: "player",
    perspectiveLabel: "Jugador",
    tab: "inicio",
  },
  {
    checks: ["Reconocer el equipo activo", "Abrir plantilla", "Encontrar invitaciones sin menús avanzados"],
    id: "team-owner",
    label: "Owner del equipo",
    objective: "Gestionar el núcleo social sin ver herramientas de plataforma.",
    perspectiveId: "team-owner",
    perspectiveLabel: "Owner",
    tab: "equipo",
  },
  {
    checks: ["Abrir Crear partido", "Completar solo los datos esenciales", "Descartar o confirmar el borrador local"],
    id: "create-match",
    label: "Crear partido",
    objective: "Crear una pachanga corta y comprensible desde Partidos.",
    perspectiveId: "team-owner",
    perspectiveLabel: "Owner",
    tab: "partido",
  },
  {
    checks: ["Elegir rival", "Enviar propuesta", "Probar contrapropuesta y aceptación"],
    id: "challenge-team",
    label: "Retar rival",
    objective: "Acordar un partido sin perder el rival ni el contexto.",
    perspectiveId: "team-owner",
    perspectiveLabel: "Owner",
    tab: "retos",
  },
  {
    checks: ["Filtrar por ubicación", "Abrir un jugador", "Volver a los mismos resultados"],
    id: "find-player",
    label: "Buscar jugador",
    objective: "Encontrar e invitar a una persona desde Mercado.",
    perspectiveId: "admin",
    perspectiveLabel: "Admin del equipo",
    tab: "mercado",
  },
  {
    checks: ["Abrir Pendientes", "Resolver en su dominio", "Comprobar que baja el contador"],
    id: "resolve-inbox",
    label: "Resolver Avisos",
    objective: "Usar la bandeja como centro de acción sin ejecutar deporte dentro de ella.",
    perspectiveId: "admin",
    perspectiveLabel: "Admin del equipo",
    tab: "avisos",
  },
];

function initialJourneyIndex() {
  if (typeof window === "undefined") return 0;
  const stored = Number(window.sessionStorage.getItem(REVIEW_SESSION_KEY));
  return Number.isInteger(stored) && stored >= 0 && stored < journeys.length ? stored : 0;
}

export function DemoSocialQuickReview({
  onClose,
  onOpenFirstTime,
  onReset,
  onStart,
}: {
  onClose: () => void;
  onOpenFirstTime: (perspectiveId: DemoWorldPerspective["id"]) => void;
  onReset: () => void;
  onStart: (tab: DemoWorldV2PrimaryTab, perspectiveId: DemoWorldPerspective["id"]) => void;
}) {
  const [index, setIndex] = useState(initialJourneyIndex);
  const dialogRef = useRef<HTMLElement>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const journey = journeys[index] ?? journeys[0];

  useEffect(() => {
    window.sessionStorage.setItem(REVIEW_SESSION_KEY, String(index));
  }, [index]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!returnFocusRef.current && document.activeElement instanceof HTMLElement) {
      returnFocusRef.current = document.activeElement;
    }
    dialog?.querySelector<HTMLElement>("button")?.focus();
    return () => {
      const returnFocus = returnFocusRef.current;
      window.requestAnimationFrame(() => {
        if (!dialog?.isConnected) returnFocus?.focus();
      });
    };
  }, []);

  function handleKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = Array.from(dialogRef.current?.querySelectorAll<HTMLElement>(
      'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ) ?? []);
    const first = focusable[0];
    const last = focusable.at(-1);
    if (!first || !last) return;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function handleProofKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const proof = event.currentTarget;
    const step = Math.max(120, Math.round(proof.clientWidth * 0.75));
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      event.preventDefault();
      proof.scrollBy({ left: event.key === "ArrowLeft" ? -step : step });
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      proof.scrollTo({ left: event.key === "Home" ? 0 : proof.scrollWidth });
    }
  }

  function reset() {
    window.sessionStorage.removeItem(REVIEW_SESSION_KEY);
    setIndex(0);
    onReset();
  }

  function openJourney() {
    if (journey.firstTime) onOpenFirstTime(journey.perspectiveId);
    else onStart(journey.tab, journey.perspectiveId);
  }

  return (
    <div className={styles.backdrop} role="presentation">
      <section className={styles.review} data-demo-social-review="v3h" role="dialog" aria-modal="true" aria-labelledby="demo-quick-review-title" onKeyDown={handleKeyDown} ref={dialogRef}>
        <header>
          <div><span>SIMULACIÓN · REVISIÓN RÁPIDA</span><h2 id="demo-quick-review-title">Recorre el núcleo social</h2></div>
          <button type="button" onClick={onClose} aria-label="Cerrar revisión rápida">×</button>
        </header>

        <div
          className={styles.proof}
          role="region"
          aria-label="Garantías de la simulación"
          tabIndex={0}
          onKeyDown={handleProofKeyDown}
        >
          <span>LOCAL SESSION ONLY</span>
          <span>remoteWrites = 0</span>
          <span>externalNotifications = 0</span>
          <span>pushSent = 0</span>
          <span>emailsSent = 0</span>
          <span>realEntities = 0</span>
          <span>StripeCalls = 0</span>
        </div>

        <nav className={styles.journeyList} aria-label="Recorridos de revisión">
          {journeys.map((item, journeyIndex) => (
            <button aria-current={journeyIndex === index ? "step" : undefined} key={item.id} type="button" onClick={() => setIndex(journeyIndex)}>
              <b>{journeyIndex + 1}</b><span>{item.label}</span>
            </button>
          ))}
        </nav>

        <div className={styles.body}>
          <div className={styles.progress}><span>Recorrido {index + 1} de {journeys.length}</span><i><b style={{ width: `${((index + 1) / journeys.length) * 100}%` }} /></i></div>
          <div className={styles.perspective}><span>Perspectiva</span><strong>{journey.perspectiveLabel}</strong></div>
          <h3>{journey.label}</h3>
          <p>{journey.objective}</p>
          <ul>{journey.checks.map((check) => <li key={check}>{check}</li>)}</ul>
          <button className={styles.primary} type="button" onClick={openJourney}>Abrir recorrido</button>
        </div>

        <footer>
          <button type="button" disabled={index === 0} onClick={() => setIndex((current) => Math.max(0, current - 1))}>Anterior</button>
          <button type="button" onClick={reset}>Reiniciar</button>
          <button type="button" onClick={() => index === journeys.length - 1 ? onClose() : setIndex((current) => Math.min(journeys.length - 1, current + 1))}>{index === journeys.length - 1 ? "Cerrar" : "Siguiente"}</button>
        </footer>
      </section>
    </div>
  );
}
