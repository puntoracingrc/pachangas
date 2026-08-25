import { leagueOperationalError, leagueOperationalJson, leagueOperationalSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await leagueOperationalSession(request);
    const url = new URL(request.url);
    const page = Math.max(0, Number.parseInt(url.searchParams.get("page") ?? "0", 10) || 0);
    const pageSize = Math.min(100, Math.max(1, Number.parseInt(url.searchParams.get("pageSize") ?? "30", 10) || 30));
    const result = await client.rpc("get_my_pachanga_league_exception_requests_v1", {
      page_offset: page * pageSize,
      page_size: pageSize,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueOperationalJson(result.data);
  } catch (error) {
    return leagueOperationalError(error);
  }
}
