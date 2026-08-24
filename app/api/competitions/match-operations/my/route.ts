import { leagueMatchError, leagueMatchJson, leagueMatchSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const page = Math.max(1, Number.parseInt(url.searchParams.get("page") ?? "1", 10) || 1);
    const pageSize = Math.min(100, Math.max(1, Number.parseInt(url.searchParams.get("pageSize") ?? "30", 10) || 30));
    const { client } = await leagueMatchSession(request);
    const result = await client.rpc("get_pachanga_my_league_match_operations_v1", {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueMatchJson(result.data);
  } catch (error) {
    return leagueMatchError(error);
  }
}
