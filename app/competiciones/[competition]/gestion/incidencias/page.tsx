import type { Metadata } from "next";
import { LeagueOperationalExceptionsClient } from "../../../../_components/league-operational-exceptions-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Incidencias de Liga · Pachangas IQ" };

export default async function LeagueIncidentDeskPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <LeagueOperationalExceptionsClient competitionId={competition} surface="incidents" />;
}
