import type { Metadata } from "next";
import { LeagueMatchOperationsClient } from "../../../../_components/league-match-operations-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Partido de Liga · Pachangas IQ" };

export default async function LeagueMatchPage({ params }: { params: Promise<{ competition: string; match: string }> }) {
  const { competition, match } = await params;
  return <LeagueMatchOperationsClient competitionId={competition} matchId={match} surface="match" />;
}
