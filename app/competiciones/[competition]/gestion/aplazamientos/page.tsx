import type { Metadata } from "next";
import { LeagueOperationalExceptionsClient } from "../../../../_components/league-operational-exceptions-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Aplazamientos de Liga · Pachangas IQ" };

export default async function LeaguePostponementDeskPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <LeagueOperationalExceptionsClient competitionId={competition} surface="postponements" />;
}
