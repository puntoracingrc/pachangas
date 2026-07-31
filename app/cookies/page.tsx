import type { Metadata } from "next";
import { LegalPage, legalPages } from "../legal-data";

export const metadata: Metadata = {
  title: "Cookies | Pachangas IQ",
  description: "Política de cookies y almacenamiento técnico de Pachangas IQ.",
};

export default function CookiesPage() {
  return <LegalPage page={legalPages.cookies} />;
}
