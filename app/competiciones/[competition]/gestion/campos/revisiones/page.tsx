import type { Metadata } from "next";
import { SeasonVenuePlannerClient } from "../../../../../_components/season-venue-planner-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Revisiones de campos · Pachangas IQ" };

export default async function CompetitionVenueRevisionsPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition } = await params;
  return <SeasonVenuePlannerClient competitionId={competition} surface="revisions" />;
}
