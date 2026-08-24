import type { Metadata } from "next";
import { LeagueMatchOperationsClient } from "../../../../_components/league-match-operations-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Mesa de resultados · Pachangas IQ" };

export default async function LeagueResultDeskPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <LeagueMatchOperationsClient competitionId={competition} surface="results" />;
}
