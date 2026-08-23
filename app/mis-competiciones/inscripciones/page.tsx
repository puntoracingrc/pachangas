import type { Metadata } from "next";
import { LeagueParticipationClient } from "../../_components/league-participation-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Mis competiciones · Pachangas IQ" };

export default function MyCompetitionEntriesPage() {
  return <LeagueParticipationClient surface="mine" />;
}
