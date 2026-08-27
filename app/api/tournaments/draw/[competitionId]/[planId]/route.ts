import { tournamentError, tournamentJson, tournamentSession, tournamentUuidPattern } from "../../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ competitionId: string; planId: string }> }) {
  try {
    const { competitionId, planId } = await context.params;
    if (!tournamentUuidPattern.test(competitionId) || !tournamentUuidPattern.test(planId)) {
      throw new Error("DRAW_PLAN_NOT_FOUND");
    }
    const { client } = await tournamentSession(request);
    const result = await client.rpc("get_pachanga_tournament_draw_desk_v1", {
      competition_id: competitionId,
      draw_plan_id: planId,
    });
    if (result.error) throw new Error(result.error.message);
    return tournamentJson(result.data);
  } catch (error) {
    return tournamentError(error);
  }
}
