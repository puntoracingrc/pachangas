import type { Metadata } from "next";
import { RefereeAssignmentsClient } from "../../../../_components/referee-assignments-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Mesa arbitral · Pachangas IQ",
};

export default async function CompetitionRefereeDeskPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <RefereeAssignmentsClient competitionId={competition} surface="competition" />;
}
