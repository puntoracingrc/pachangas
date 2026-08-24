import {
  leagueMatchError,
  leagueMatchJson,
  leagueMatchSession,
  leagueMatchUuidPattern,
} from "../../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string; matchId: string }> }) {
  try {
    const { competitionId, matchId } = await params;
    if (!leagueMatchUuidPattern.test(competitionId) || !leagueMatchUuidPattern.test(matchId)) {
      throw new Error("COMPETITION_MATCH_CONTEXT_NOT_FOUND");
    }
    const { client } = await leagueMatchSession(request);
    const result = await client.rpc("get_pachanga_league_canonical_match_v1", {
      target_canonical_match_id: matchId,
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueMatchJson(result.data);
  } catch (error) {
    return leagueMatchError(error);
  }
}
