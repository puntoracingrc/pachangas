import {
  leagueMatchError,
  leagueMatchJson,
  leagueMatchSession,
  leagueMatchUuidPattern,
} from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const states = new Set(["", "submitted", "change_proposed", "confirmed", "disputed", "official", "annulled"]);

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!leagueMatchUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const url = new URL(request.url);
    const state = (url.searchParams.get("state") ?? "").toLowerCase();
    const page = Math.max(1, Number.parseInt(url.searchParams.get("page") ?? "1", 10) || 1);
    const pageSize = Math.min(100, Math.max(1, Number.parseInt(url.searchParams.get("pageSize") ?? "50", 10) || 50));
    if (!states.has(state)) throw new Error("INVALID_LEAGUE_RESULT_FILTER");
    const { client } = await leagueMatchSession(request);
    const result = await client.rpc("get_pachanga_league_result_desk_v1", {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
      target_competition_id: competitionId,
      target_state: state || null,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueMatchJson(result.data);
  } catch (error) {
    return leagueMatchError(error);
  }
}
