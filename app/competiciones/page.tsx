import type { Metadata } from "next";
import { searchPublicCompetitions } from "../public-product-data";
import { CompetitionDirectoryClient } from "./competition-directory-client";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  alternates: { canonical: "https://pachangasiq.com/competiciones" },
  description: "Encuentra Ligas y Torneos públicos, consulta su calendario y solicita la inscripción de tu equipo.",
  openGraph: {
    description: "Ligas y Torneos públicos con calendario, clasificación y cuadro canónicos.",
    title: "Competiciones | Pachangas IQ",
    type: "website",
    url: "https://pachangasiq.com/competiciones",
  },
  robots: { follow: true, index: true },
  title: "Competiciones | Pachangas IQ",
};

export default async function PublicCompetitionsPage() {
  const initial = await searchPublicCompetitions({}, 1, 24);
  return <CompetitionDirectoryClient initialData={initial && typeof initial === "object" && !Array.isArray(initial) ? initial as Record<string, unknown> : null} />;
}
