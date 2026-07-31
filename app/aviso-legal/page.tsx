import type { Metadata } from "next";
import { LegalPage, legalPages } from "../legal-data";

export const metadata: Metadata = {
  title: "Aviso legal | Pachangas IQ",
  description: "Información legal del titular y uso de Pachangas IQ.",
};

export default function AvisoLegalPage() {
  return <LegalPage page={legalPages.avisoLegal} />;
}
