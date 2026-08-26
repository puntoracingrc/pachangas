import { refereeError, refereeJson, refereeSession, refereeUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ matchId: string }> }) {
  try {
    const { matchId } = await params;
    if (!refereeUuidPattern.test(matchId)) throw new Error("REFEREE_MATCH_NOT_FOUND");
    const { client } = await refereeSession(request);
    const result = await client.rpc("get_pachanga_referee_match_assignment_v1", {
      target_canonical_match_id: matchId,
    });
    if (result.error) return refereeError(result.error);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
