import type { Metadata } from "next";
import { LeagueSchedulingClient } from "../../../../_components/league-scheduling-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Jornada de Liga · Pachangas IQ" };

export default async function CompetitionRoundPage({ params }: { params: Promise<{ competition: string; round: string }> }) {
  const { competition, round } = await params;
  return <LeagueSchedulingClient competitionId={competition} roundId={round} surface="round" />;
}
