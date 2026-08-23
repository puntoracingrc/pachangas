import type { Metadata } from "next";
import { LeagueSchedulingClient } from "../../_components/league-scheduling-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Mi calendario de Liga · Pachangas IQ" };

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function MyLeagueCalendarPage({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const query = await searchParams;
  return <LeagueSchedulingClient entryId={first(query.entry)} surface="team" />;
}
