import Home from "../../../page";

export default async function SharedMatchPage({
  params,
}: {
  params: Promise<{ matchId: string; teamCode: string }>;
}) {
  const { matchId, teamCode } = await params;
  return <Home entryRoute={{ matchId, teamCode }} />;
}
