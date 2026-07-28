import type { Metadata } from "next";
import Link from "next/link";
import { ManualContent } from "../manual-content";

export const metadata: Metadata = {
  title: "Manual de usuario | Pachanga IQ",
  description: "Guía rápida para usar Pachanga IQ.",
};

export default function ManualPage() {
  return (
    <main className="manual-page">
      <section className="manual-hero">
        <div>
          <p className="eyebrow">Pachanga IQ</p>
          <h1>Manual de usuario</h1>
          <p className="hero-copy">
            Guía rápida de secciones para entender el flujo de equipo, partidos, jugadores, valoraciones y ranking.
          </p>
        </div>
        <Link className="secondary-button manual-back-button" href="/">
          Volver
        </Link>
      </section>

      <section className="top-panel manual-page-panel">
        <div className="manual-page-title">
          <span>Guía rápida</span>
          <strong>Secciones principales</strong>
        </div>
        <ManualContent />
      </section>
    </main>
  );
}
