import type { Metadata } from "next";
import { LeagueMatchOperationsClient } from "../../../_components/league-match-operations-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Clasificación de Liga · Pachangas IQ" };

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function LeagueStandingsPage({ params, searchParams }: {
  params: Promise<{ competition: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ competition }, query] = await Promise.all([params, searchParams]);
  return <LeagueMatchOperationsClient
    competitionId={competition}
    divisionId={first(query.division)}
    groupId={first(query.group)}
    publicView={first(query.public) === "1"}
    stageId={first(query.stage)}
    surface="standings"
  />;
}
