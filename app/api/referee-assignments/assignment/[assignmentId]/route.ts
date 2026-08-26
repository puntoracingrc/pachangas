import { refereeError, refereeJson, refereeSession, refereeUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ assignmentId: string }> }) {
  try {
    const { assignmentId } = await params;
    if (!refereeUuidPattern.test(assignmentId)) throw new Error("REFEREE_ASSIGNMENT_NOT_FOUND");
    const { client } = await refereeSession(request);
    const result = await client.rpc("get_pachanga_referee_assignment_beta_v1", {
      target_assignment_id: assignmentId,
    });
    if (result.error) return refereeError(result.error);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
