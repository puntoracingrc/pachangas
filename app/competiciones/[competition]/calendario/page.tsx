import type { Metadata } from "next";
import { LeagueSchedulingClient } from "../../../_components/league-scheduling-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Calendario de Liga · Pachangas IQ" };

export default async function PublicCompetitionCalendarPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <LeagueSchedulingClient competitionId={competition} surface="public" />;
}
