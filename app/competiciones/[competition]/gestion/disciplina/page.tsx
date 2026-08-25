import type { Metadata } from "next";
import { CompetitionDisciplineClient } from "../../../../_components/competition-discipline-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Mesa disciplinaria · Pachangas IQ" };

export default async function CompetitionDisciplineDeskPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <CompetitionDisciplineClient competitionId={competition} surface="desk" />;
}
