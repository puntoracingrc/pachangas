import { disciplineError, disciplineJson, disciplineSession, disciplineUuidPattern } from "../../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ competitionId: string; playerId: string }> }) {
  try {
    const { competitionId, playerId } = await context.params;
    if (!disciplineUuidPattern.test(competitionId) || !disciplineUuidPattern.test(playerId)) {
      throw new Error("PLAYER_DISCIPLINE_NOT_FOUND");
    }
    const { client } = await disciplineSession(request);
    const result = await client.rpc("get_pachanga_competition_discipline_v1", {
      target_canonical_match_id: null,
      target_competition_id: competitionId,
      target_player_profile_id: playerId,
    });
    if (result.error) throw new Error(result.error.message);
    return disciplineJson(result.data);
  } catch (error) {
    return disciplineError(error);
  }
}
