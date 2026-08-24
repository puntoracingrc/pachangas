import {
  leagueMatchError,
  leagueMatchJson,
  leagueMatchPublicClient,
  leagueMatchSession,
  leagueMatchUuidPattern,
} from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function optionalUuid(value: string | null) {
  if (!value) return null;
  if (!leagueMatchUuidPattern.test(value)) throw new Error("INVALID_LEAGUE_STANDINGS_SCOPE");
  return value;
}

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    const url = new URL(request.url);
    const stageId = url.searchParams.get("stage");
    if (!leagueMatchUuidPattern.test(competitionId) || !stageId || !leagueMatchUuidPattern.test(stageId)) {
      throw new Error("INVALID_LEAGUE_STANDINGS_SCOPE");
    }
    const rpcArgs = {
      target_competition_id: competitionId,
      target_division_id: optionalUuid(url.searchParams.get("division")),
      target_group_id: optionalUuid(url.searchParams.get("group")),
      target_stage_id: stageId,
    };
    const publicRead = url.searchParams.get("public") === "1";
    const client = publicRead ? leagueMatchPublicClient() : (await leagueMatchSession(request)).client;
    const result = await client.rpc(
      publicRead ? "get_pachanga_public_league_standings_v1" : "get_pachanga_league_standings_v1",
      rpcArgs,
    );
    if (result.error) throw new Error(result.error.message);
    return leagueMatchJson(result.data);
  } catch (error) {
    return leagueMatchError(error);
  }
}
