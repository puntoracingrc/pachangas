import type { Metadata } from "next";
import { LegalPage, legalPages } from "../legal-data";

export const metadata: Metadata = {
  title: "Privacidad | Pachangas IQ",
  description: "Política de privacidad y tratamiento de datos personales en Pachangas IQ.",
};

export default function PrivacidadPage() {
  return <LegalPage page={legalPages.privacidad} />;
}
