import type { Metadata } from "next";
import { LegalPage, legalPages } from "../legal-data";

export const metadata: Metadata = {
  title: "Condiciones de venta | Pachangas IQ",
  description: "Condiciones de contratación, suscripciones, pagos y prueba gratuita de Pachangas IQ.",
};

export default function CondicionesVentaPage() {
  return <LegalPage page={legalPages.condicionesVenta} />;
}
