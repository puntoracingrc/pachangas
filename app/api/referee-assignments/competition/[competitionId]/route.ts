import { refereeError, refereeJson, refereeSession, refereeUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!refereeUuidPattern.test(competitionId)) throw new Error("REFEREE_COMPETITION_NOT_FOUND");
    const { client } = await refereeSession(request);
    const result = await client.rpc("get_pachanga_referee_competition_desk_v1", {
      target_competition_id: competitionId,
    });
    if (result.error) return refereeError(result.error);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
