import type { Metadata } from "next";
import { LeagueOperationalExceptionsClient } from "../../_components/league-operational-exceptions-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Mis solicitudes de Liga · Pachangas IQ" };

export default function MyLeagueExceptionRequestsPage() {
  return <LeagueOperationalExceptionsClient surface="my" />;
}
