import { refereeError, refereeJson, refereeSession, refereeUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ clubId: string }> }) {
  try {
    const { clubId } = await params;
    if (!refereeUuidPattern.test(clubId)) throw new Error("CLUB_REFEREE_NOT_FOUND");
    const { client } = await refereeSession(request);
    const result = await client.rpc("get_pachanga_referee_club_assignments_v1", {
      target_club_id: clubId,
    });
    if (result.error) return refereeError(result.error);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
