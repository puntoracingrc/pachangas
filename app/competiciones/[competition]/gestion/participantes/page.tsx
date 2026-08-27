import type { Metadata } from "next";
import { TournamentPrivateBetaClient } from "../../../../_components/tournament-private-beta-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Participantes del Torneo · Pachangas IQ",
};

export default async function TournamentParticipantsPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <TournamentPrivateBetaClient competitionId={competition} surface="participants" />;
}
