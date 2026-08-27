import type { Metadata } from "next";
import { TournamentPrivateBetaClient } from "../../_components/tournament-private-beta-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Crear Torneo privado · Pachangas IQ",
};

export default function CreateTournamentPage() {
  return <TournamentPrivateBetaClient surface="wizard" />;
}
