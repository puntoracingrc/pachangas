import type { Metadata } from "next";
import { CompetitionDisciplineClient } from "../../../_components/competition-discipline-client";

export const metadata: Metadata = { title: "Disciplina de Liga · Pachangas IQ" };

export default async function PublicCompetitionDisciplinePage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <CompetitionDisciplineClient competitionId={competition} surface="public" />;
}
