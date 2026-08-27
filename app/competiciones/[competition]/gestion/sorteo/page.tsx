import type { Metadata } from "next";
import { TournamentPrivateBetaClient } from "../../../../_components/tournament-private-beta-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Mesa de sorteo · Pachangas IQ",
};

export default async function TournamentDrawDeskPage({ params, searchParams }: {
  params: Promise<{ competition: string }>;
  searchParams: Promise<{ plan?: string }>;
}) {
  const [{ competition }, query] = await Promise.all([params, searchParams]);
  return <TournamentPrivateBetaClient competitionId={competition} planId={query.plan ?? ""} surface="desk" />;
}
