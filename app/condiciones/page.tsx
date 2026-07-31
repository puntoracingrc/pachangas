import type { Metadata } from "next";
import { LegalPage, legalPages } from "../legal-data";

export const metadata: Metadata = {
  title: "Condiciones de uso | Pachangas IQ",
  description: "Condiciones de uso para jugadores, admins y owners en Pachangas IQ.",
};

export default function CondicionesPage() {
  return <LegalPage page={legalPages.condiciones} />;
}
