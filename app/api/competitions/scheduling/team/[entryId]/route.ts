import { scheduleError, scheduleJson, scheduleSession, scheduleUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ entryId: string }> }) {
  try {
    const { entryId } = await params;
    if (!scheduleUuidPattern.test(entryId)) throw new Error("ENTRY_NOT_FOUND");
    const { client } = await scheduleSession(request);
    const result = await client.rpc("get_pachanga_my_league_schedule_v1", { target_entry_id: entryId });
    if (result.error) throw new Error(result.error.message);
    return scheduleJson(result.data);
  } catch (error) {
    return scheduleError(error);
  }
}
