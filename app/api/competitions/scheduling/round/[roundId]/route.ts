import { scheduleError, scheduleJson, schedulePublicClient, scheduleSession, scheduleUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ roundId: string }> }) {
  try {
    const { roundId } = await params;
    if (!scheduleUuidPattern.test(roundId)) throw new Error("ROUND_NOT_FOUND");
    const authorization = (request.headers.get("authorization") ?? "").trim();
    const client = authorization ? (await scheduleSession(request)).client : schedulePublicClient();
    const result = await client.rpc("get_pachanga_league_round_detail_v1", { target_round_id: roundId });
    if (result.error) throw new Error(result.error.message);
    return scheduleJson(result.data);
  } catch (error) {
    return scheduleError(error);
  }
}
