import type { Metadata } from "next";
import { TournamentPrivateBetaClient } from "../_components/tournament-private-beta-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Torneos privados · Pachangas IQ",
};

export default function TournamentsPage() {
  return <TournamentPrivateBetaClient surface="home" />;
}
