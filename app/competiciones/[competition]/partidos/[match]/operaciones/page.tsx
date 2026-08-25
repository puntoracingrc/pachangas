import type { Metadata } from "next";
import { LeagueOperationalExceptionsClient } from "../../../../../_components/league-operational-exceptions-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Operaciones del partido · Pachangas IQ" };

export default async function LeagueOperationalMatchPage({ params }: { params: Promise<{ competition: string; match: string }> }) {
  const { competition, match } = await params;
  return <LeagueOperationalExceptionsClient competitionId={competition} matchId={match} surface="match" />;
}
