import {
  tournamentError,
  tournamentJson,
  tournamentSession,
  tournamentUuidPattern,
} from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await context.params;
    if (!tournamentUuidPattern.test(competitionId)) throw new Error("TOURNAMENT_BRACKET_NOT_FOUND");
    const { client } = await tournamentSession(request);
    const result = await client.rpc("get_pachanga_tournament_knockout_v1", {
      competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return tournamentJson(result.data);
  } catch (error) {
    return tournamentError(error);
  }
}
