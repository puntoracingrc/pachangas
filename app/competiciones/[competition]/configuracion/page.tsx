import type { Metadata } from "next";
import { CompetitionConfigurationClient } from "../../../_components/competition-configuration-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Configuración de competición · Pachangas IQ" };

export default async function CompetitionConfigurationPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <CompetitionConfigurationClient competitionId={competition} />;
}
