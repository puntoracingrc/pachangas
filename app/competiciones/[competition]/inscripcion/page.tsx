import type { Metadata } from "next";
import { LeagueParticipationClient } from "../../../_components/league-participation-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Inscripción de Liga · Pachangas IQ" };

export default async function LeagueRegistrationPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <LeagueParticipationClient competitionId={competition} surface="public" />;
}
