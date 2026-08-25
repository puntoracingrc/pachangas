import {
  leagueOperationalError,
  leagueOperationalJson,
  leagueOperationalPublicClient,
  leagueOperationalUuidPattern,
} from "../../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(_request: Request, { params }: { params: Promise<{ competitionId: string; matchId: string }> }) {
  try {
    const { competitionId, matchId } = await params;
    if (!leagueOperationalUuidPattern.test(competitionId) || !leagueOperationalUuidPattern.test(matchId)) {
      throw new Error("PUBLIC_FIXTURE_NOT_FOUND");
    }
    const result = await leagueOperationalPublicClient().rpc("get_pachanga_public_league_fixture_status_v1", {
      target_canonical_match_id: matchId,
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueOperationalJson(result.data);
  } catch (error) {
    return leagueOperationalError(error);
  }
}
