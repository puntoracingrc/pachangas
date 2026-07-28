import type { Metadata } from "next";
import Link from "next/link";
import { ManualContent } from "../manual-content";

export const metadata: Metadata = {
  title: "Manual de usuario | Pachangas IQ",
  description: "Guía de flujos para jugadores y admins de Pachangas IQ.",
};

export default function ManualPage() {
  return (
    <main className="manual-page">
      <section className="manual-hero">
        <div>
          <p className="eyebrow">Pachangas IQ</p>
          <h1>Manual de usuario</h1>
          <p className="hero-copy">
            Flujos completos para jugadores y admins: registro, equipos, partidos, reservas, pagos, fichas, valoraciones, historial y ranking.
          </p>
        </div>
        <Link className="secondary-button manual-back-button" href="/">
          Volver
        </Link>
      </section>

      <section className="top-panel manual-page-panel">
        <div className="manual-page-title">
          <span>Guía de uso</span>
          <strong>Jugador y admin</strong>
        </div>
        <ManualContent />
      </section>
    </main>
  );
}
