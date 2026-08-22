import { leagueError, leagueJson, leagueSession, leagueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!leagueUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const { client } = await leagueSession(request);
    const url = new URL(request.url);
    const categoryId = url.searchParams.get("category") ?? "";
    if (categoryId && !leagueUuidPattern.test(categoryId)) throw new Error("INVALID_CATEGORY_FILTER");
    const page = bounded(url.searchParams.get("page"), 1, 100000);
    const pageSize = bounded(url.searchParams.get("pageSize"), 30, 100);
    const result = await client.rpc("get_pachanga_competition_registration_desk_v1", {
      category_filter: categoryId || null,
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
      status_filter: url.searchParams.get("status") || null,
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueJson({ ...result.data, page, pageSize });
  } catch (error) {
    return leagueError(error);
  }
}
