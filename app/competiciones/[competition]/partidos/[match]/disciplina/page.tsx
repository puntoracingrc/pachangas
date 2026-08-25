import type { Metadata } from "next";
import { CompetitionDisciplineClient } from "../../../../../_components/competition-discipline-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Disciplina del partido · Pachangas IQ" };

export default async function CompetitionMatchDisciplinePage({ params }: { params: Promise<{ competition: string; match: string }> }) {
  const { competition, match } = await params;
  return <CompetitionDisciplineClient competitionId={competition} matchId={match} surface="match" />;
}
