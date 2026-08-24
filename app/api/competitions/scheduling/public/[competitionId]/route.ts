import { scheduleError, scheduleJson, schedulePublicClient, scheduleUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!scheduleUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const url = new URL(request.url);
    const page = bounded(url.searchParams.get("page"), 1, 100000);
    const pageSize = bounded(url.searchParams.get("pageSize"), 100, 200);
    const result = await schedulePublicClient().rpc("get_pachanga_public_league_calendar_v1", {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return scheduleJson({ ...result.data, page, pageSize });
  } catch (error) {
    return scheduleError(error);
  }
}
