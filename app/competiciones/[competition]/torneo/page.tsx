import type { Metadata } from "next";
import { TournamentGroupStageClient } from "../../../_components/tournament-group-stage-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Tournament Hub · Pachangas IQ",
};

export default async function TournamentGroupStagePage({ params }: {
  params: Promise<{ competition: string }>;
}) {
  const { competition } = await params;
  return <TournamentGroupStageClient competitionId={competition} />;
}
