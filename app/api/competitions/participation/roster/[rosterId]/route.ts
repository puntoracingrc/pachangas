import { leagueError, leagueJson, leagueSession, leagueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request, { params }: { params: Promise<{ rosterId: string }> }) {
  try {
    const { rosterId } = await params;
    if (!leagueUuidPattern.test(rosterId)) throw new Error("ROSTER_NOT_FOUND");
    const { client } = await leagueSession(request);
    const url = new URL(request.url);
    const page = bounded(url.searchParams.get("page"), 1, 100000);
    const pageSize = bounded(url.searchParams.get("pageSize"), 50, 100);
    const result = await client.rpc("get_pachanga_competition_roster_v1", {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
      target_roster_id: rosterId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueJson({ ...result.data, page, pageSize });
  } catch (error) {
    return leagueError(error);
  }
}
