import { leagueOperationalError, leagueOperationalJson, leagueOperationalSession, leagueOperationalUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!leagueOperationalUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const { client } = await leagueOperationalSession(request);
    const url = new URL(request.url);
    const result = await client.rpc("get_pachanga_league_administrative_decision_desk_v1", {
      page_offset: Math.max(0, Number.parseInt(url.searchParams.get("offset") ?? "0", 10) || 0),
      page_size: Math.min(300, Math.max(1, Number.parseInt(url.searchParams.get("limit") ?? "100", 10) || 100)),
      status_filter: url.searchParams.get("status") || null,
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueOperationalJson(result.data);
  } catch (error) {
    return leagueOperationalError(error);
  }
}
