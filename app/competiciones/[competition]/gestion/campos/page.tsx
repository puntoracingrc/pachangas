import type { Metadata } from "next";
import { SeasonVenuePlannerClient } from "../../../../_components/season-venue-planner-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Campos de competición · Pachangas IQ" };

export default async function CompetitionVenuesPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <SeasonVenuePlannerClient competitionId={competition} surface="competition" />;
}
