import type { Metadata } from "next";
import { LeagueMatchOperationsClient } from "../../_components/league-match-operations-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Mis partidos de Liga · Pachangas IQ" };

export default function MyLeagueMatchesPage() {
  return <LeagueMatchOperationsClient surface="my" />;
}
