import { disciplineError, disciplineJson, disciplineSession, disciplineUuidPattern } from "../../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ competitionId: string; matchId: string }> }) {
  try {
    const { competitionId, matchId } = await context.params;
    if (!disciplineUuidPattern.test(competitionId) || !disciplineUuidPattern.test(matchId)) {
      throw new Error("DISCIPLINE_MATCH_CONTEXT_NOT_FOUND");
    }
    const { client } = await disciplineSession(request);
    const result = await client.rpc("get_pachanga_competition_discipline_v1", {
      target_canonical_match_id: matchId,
      target_competition_id: competitionId,
      target_player_profile_id: null,
    });
    if (result.error) throw new Error(result.error.message);
    return disciplineJson(result.data);
  } catch (error) {
    return disciplineError(error);
  }
}
