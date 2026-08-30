"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import {
  DEMO_WORLD_V33_TOURS,
  demoWorldV33StepHref,
  type DemoWorldV33TourId,
} from "./demo-world-v3-3-contract";
import styles from "./demo-world-v3-3-guided-review.module.css";

const progressKey = "pachangas-demo-v3-3-guided-progress";

function readProgress() {
  if (typeof window === "undefined") return [] as string[];
  try {
    const value = JSON.parse(window.localStorage.getItem(progressKey) ?? "[]") as unknown;
    return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
  } catch {
    return [];
  }
}

export function DemoWorldV33GuidedReview() {
  const [completed, setCompleted] = useState<string[]>(readProgress);
  const [selectedTourId, setSelectedTourId] = useState<DemoWorldV33TourId>(() => {
    if (typeof window === "undefined") return DEMO_WORLD_V33_TOURS[0]!.id;
    const requested = new URLSearchParams(window.location.search).get("tour");
    return DEMO_WORLD_V33_TOURS.some(({ id }) => id === requested) ? requested as DemoWorldV33TourId : DEMO_WORLD_V33_TOURS[0]!.id;
  });

  const selectedTour = useMemo(
    () => DEMO_WORLD_V33_TOURS.find(({ id }) => id === selectedTourId) ?? DEMO_WORLD_V33_TOURS[0]!,
    [selectedTourId],
  );

  function markStep(stepId: string) {
    const next = [...new Set([...completed, `${selectedTour.id}:${stepId}`])];
    setCompleted(next);
    window.localStorage.setItem(progressKey, JSON.stringify(next));
  }

  return (
    <section className={styles.review} data-demo-guided-review="v3.3">
      <header className={styles.hero}>
        <div><span>Mundo Demo V3.3</span><h1>Revisión guiada del producto</h1><p>Ocho recorridos conectan el producto oficial con snapshots sintéticos. Navegar no ejecuta RPC ni modifica datos remotos.</p></div>
        <details><summary>Qué estoy viendo</summary><p>Una capa de presentación sobre la autoridad inmutable V3.2. El progreso se guarda solo en este navegador.</p></details>
      </header>
      <div className={styles.layout}>
        <nav aria-label="Recorridos de producto">
          {DEMO_WORLD_V33_TOURS.map((tour) => (
            <button aria-current={selectedTour.id === tour.id ? "page" : undefined} key={tour.id} type="button" onClick={() => setSelectedTourId(tour.id)}>
              <strong>{tour.label}</strong><small>{tour.steps.length} pasos</small>
            </button>
          ))}
        </nav>
        <div className={styles.workspace}>
          <header><span>Recorrido</span><h2>{selectedTour.label}</h2><p>{selectedTour.description}</p></header>
          <ol>
            {selectedTour.steps.map((step, index) => {
              const done = completed.includes(`${selectedTour.id}:${step.id}`);
              return <li data-complete={done} key={step.id}>
                <span>{index + 1}</span>
                <div><strong>{step.title}</strong><p>{step.description}</p><small>{step.comparison}</small></div>
                <Link href={demoWorldV33StepHref(selectedTour, index)} onClick={() => markStep(step.id)}>{done ? "Revisar" : "Abrir"}</Link>
              </li>;
            })}
          </ol>
          <section className={styles.comparison} aria-label="Comparación Demo y producto">
            <div><span>Producto oficial</span><strong>RPC/API central</strong><p>Permisos, idempotencia, revisión y snapshot canónico.</p></div>
            <div><span>Mundo Demo</span><strong>Lectura inmutable</strong><p>Mismo lenguaje visual, datos ficticios y cero escrituras remotas.</p></div>
          </section>
        </div>
      </div>
    </section>
  );
}
