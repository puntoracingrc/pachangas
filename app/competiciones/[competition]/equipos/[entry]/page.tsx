import type { Metadata } from "next";
import { LeagueParticipationClient } from "../../../../_components/league-participation-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Participación del equipo · Pachangas IQ" };

export default async function CompetitionEntryPage({ params, searchParams }: { params: Promise<{ competition: string; entry: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const [{ competition, entry }, query] = await Promise.all([params, searchParams]);
  const roster = Array.isArray(query.roster) ? query.roster[0] : query.roster;
  return roster
    ? <LeagueParticipationClient competitionId={competition} entryId={entry} rosterId={roster} surface="roster" />
    : <LeagueParticipationClient competitionId={competition} entryId={entry} surface="entry" />;
}
