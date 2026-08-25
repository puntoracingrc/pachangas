import type { Metadata } from "next";
import { CompetitionDisciplineClient } from "../../../../../_components/competition-discipline-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Disciplina del jugador · Pachangas IQ" };

export default async function CompetitionPlayerDisciplinePage({ params }: { params: Promise<{ competition: string; player: string }> }) {
  const { competition, player } = await params;
  return <CompetitionDisciplineClient competitionId={competition} playerId={player} surface="player" />;
}
