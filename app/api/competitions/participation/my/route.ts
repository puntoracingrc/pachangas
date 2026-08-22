import { leagueError, leagueJson, leagueSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request) {
  try {
    const { client } = await leagueSession(request);
    const url = new URL(request.url);
    const page = bounded(url.searchParams.get("page"), 1, 100000);
    const pageSize = bounded(url.searchParams.get("pageSize"), 30, 100);
    const result = await client.rpc("get_my_pachanga_competition_entries_v1", {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueJson({ ...result.data, page, pageSize });
  } catch (error) {
    return leagueError(error);
  }
}
