import { scheduleError, scheduleJson, scheduleSession, scheduleUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request, { params }: { params: Promise<{ planId: string }> }) {
  try {
    const { planId } = await params;
    if (!scheduleUuidPattern.test(planId)) throw new Error("SCHEDULE_PLAN_NOT_FOUND");
    const { client } = await scheduleSession(request);
    const url = new URL(request.url);
    const page = bounded(url.searchParams.get("page"), 1, 100000);
    const pageSize = bounded(url.searchParams.get("pageSize"), 200, 500);
    const result = await client.rpc("get_pachanga_league_schedule_workbench_v1", {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
      target_schedule_plan_id: planId,
    });
    if (result.error) throw new Error(result.error.message);
    return scheduleJson({ ...result.data, page, pageSize });
  } catch (error) {
    return scheduleError(error);
  }
}
