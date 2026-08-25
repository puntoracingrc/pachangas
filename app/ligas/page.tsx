import type { Metadata } from "next";
import { LeaguePrivateBetaClient } from "../_components/league-private-beta-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Ligas (Beta) · Pachangas IQ",
};

export default function LeaguePrivateBetaPage() {
  return <LeaguePrivateBetaClient />;
}
